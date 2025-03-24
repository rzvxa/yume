const std = @import("std");

const Uuid = @import("uuid.zig");
const Vec3 = @import("math3d.zig").Vec3;
const Mat4 = @import("math3d.zig").Mat4;
const Quat = @import("math3d.zig").Quat;
const utils = @import("utils.zig");
const MeshRenderer = @import("components/MeshRenderer.zig");
const Camera = @import("components/Camera.zig");
const BoundingBox = @import("mesh.zig").BoundingBox;

pub const Scene = struct {
    const Self = @This();

    root: *Object,
    main_camera: ?*Camera = null,
    renderables: std.ArrayList(*MeshRenderer),
    live_object: std.ArrayList(*Object),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .renderables = std.ArrayList(*MeshRenderer).init(allocator),
            .live_object = std.ArrayList(*Object).init(allocator),
            .root = undefined,
        };
        self.root = Object.create(self, try allocator.dupeZ(u8, "root"), Mat4.IDENTITY) catch @panic("OOM");
        try self.live_object.append(self.root.ref());

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.renderables.deinit();
        if (self.main_camera) |main_camera| {
            main_camera.object.deref();
            self.main_camera = null;
        }
        self.root.clear(true);
        self.root.deref();
        for (self.live_object.items) |obj| {
            if (obj.refc > 1) {
                std.log.debug("meamory leak! obj name: {s}, refc: {}", .{ obj.name, obj.refc - 1 });
                @panic("meamory leak!");
            }
            obj.deref();
        }
        self.live_object.deinit();
        self.allocator.destroy(self);
    }

    pub fn newObject(self: *Scene, options: struct {
        name: ?[:0]u8 = null,
        parent: ?*Object = null,
        transform: Mat4 = Mat4.IDENTITY,
    }) !*Object {
        const parent = blk: {
            if (options.parent) |parent| {
                if (parent.scene != self) {
                    return error.InvalidParent;
                }
                break :blk parent;
            } else {
                break :blk self.root;
            }
        };
        const name = if (options.name) |n| n else parent.scene.allocator.dupeZ(u8, "Object") catch @panic("OOM");
        const obj = Object.create(self, name, options.transform) catch @panic("OOM");
        self.live_object.append(obj) catch @panic("OOM");
        parent.addChildren(obj);
        return obj.ref();
    }

    pub fn dfs(self: *Scene) std.mem.Allocator.Error!Dfs {
        return try Dfs.init(self.allocator, self.root);
    }

    pub fn fromJson(
        allocator: std.mem.Allocator,
        json: []const u8,
        o: std.json.ParseOptions,
    ) !*Self {
        var scanner = std.json.Scanner.initCompleteInput(allocator, json);
        defer scanner.deinit();

        var jrs = &scanner;

        var tk = try jrs.next();
        if (tk != .object_begin) return error.UnexpectedEndOfInput;

        var result = try allocator.create(Self);
        result.* = Self{
            .allocator = allocator,
            .renderables = std.ArrayList(*MeshRenderer).init(allocator),
            .live_object = std.ArrayList(*Object).init(allocator),
            .root = undefined,
        };

        while (true) {
            tk = try jrs.nextAlloc(allocator, .alloc_if_needed);
            if (tk == .object_end) break;

            const field_name = switch (tk) {
                inline .string, .allocated_string => |slice| slice,
                else => {
                    std.debug.print("{}\n", .{tk});
                    return error.UnexpectedToken;
                },
            };

            if (std.mem.eql(u8, field_name, "root")) {
                var ptrmap = std.AutoHashMap(Uuid, *anyopaque).init(allocator);
                defer ptrmap.deinit();
                result.root = try Object.jsonParseGraph(allocator, jrs, o, .{
                    .scene = result,
                    .ptrmap = &ptrmap,
                });
            } else {
                try jrs.skipValue();
            }
        }

        return result;
    }

    pub fn jsonStringify(self: Self, jws: anytype) !void {
        try jws.beginObject();

        try jws.objectField("root");
        try self.root.jsonStringifyGraph(jws);
        try jws.endObject();
    }
};

pub const Dfs = struct {
    const Self = @This();

    stack: std.ArrayList(*Object),

    pub fn init(allocator: std.mem.Allocator, root: *Object) !Self {
        var self = Self{
            .stack = try std.ArrayList(*Object).initCapacity(allocator, 1),
        };
        self.stack.appendAssumeCapacity(root.ref());
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.stack.items) |o| {
            o.deinit();
        }
        self.stack.deinit();
    }

    // the caller is responsible to deref the returned object
    pub fn next(self: *Self) !?*Object {
        if (self.stack.items.len == 0) return null;

        const obj = self.stack.pop();
        for (obj.children.items) |o| {
            try self.stack.append(o.ref());
        }
        return obj;
    }
};

const ComponentDeinitializer = struct {
    ptr: *anyopaque,
    deinitalizer: *const fn (allocator: std.mem.Allocator, ptr: *anyopaque) void,
};

pub const Object = struct {
    const Self = @This();

    refc: u32 = 1,

    uuid: Uuid,
    name: [:0]u8,
    transform: Transform,
    parent: ?*Object = null,
    children: std.ArrayList(*Object),
    components: std.ArrayList(Component),
    components_deinit_handles: std.ArrayList(ComponentDeinitializer),
    scene: *Scene,

    pub fn create(scene: *Scene, name: [:0]u8, transform: Mat4) !*Object {
        const self = try scene.allocator.create(Self);
        self.* = .{
            .uuid = Uuid.new(),
            .name = name,
            .transform = Transform.fromMatrix(transform),
            .children = std.ArrayList(*Object).init(scene.allocator),
            .components = std.ArrayList(Component).init(scene.allocator),
            .components_deinit_handles = std.ArrayList(ComponentDeinitializer).init(scene.allocator),

            .scene = scene,
        };
        return self;
    }

    pub fn ref(self: *Self) *Self {
        self.refc += 1;
        return self;
    }

    // returns true if we had the last reference and object destroyed.
    pub fn deref(self: *Self) void {
        self.refc -= 1;
        if (self.refc == 0) {
            self.deinit();
        }
    }

    pub fn clear(self: *Self, recursive: bool) void {
        var i: usize = self.children.items.len;
        while (i > 0) {
            i -= 1;
            const child = self.children.items[i];
            if (recursive) {
                child.clear(true);
            }
            self.removeChildren(child);
        }
    }

    fn deinit(self: *Self) void {
        var i: usize = self.children.items.len;
        while (i > 0) {
            i -= 1;
            self.removeChildren(self.children.items[i]);
        }
        self.children.deinit();
        for (self.components.items) |component| {
            component.deinit(component.ptr);
        }
        self.components.deinit();
        for (self.components_deinit_handles.items) |handle| {
            handle.deinitalizer(self.scene.allocator, handle.ptr);
        }
        self.components_deinit_handles.deinit();
        self.scene.allocator.free(self.name);
        self.scene.allocator.destroy(self);
    }

    pub fn addComponent(self: *Self, comptime ComponentType: type, init_options: @typeInfo(@TypeOf(ComponentType.init)).Fn.params[1].type.?) void {
        const component = self.scene.allocator.create(ComponentType) catch @panic("OOM");
        component.* = ComponentType.init(self, init_options);

        const interface = component.asComponent();
        const def = ComponentType.definition();
        self.addComponentPtr(&def, interface);
    }

    pub fn addComponentDynamic(self: *Self, def: *const ComponentDefinition) void {
        const component = def.create_default(self.scene.allocator, self) catch @panic("Failed to add component dynamically");
        self.addComponentPtr(def, component);
    }

    pub fn addComponentPtr(self: *Self, def: *const ComponentDefinition, component: Component) void {
        var component_var = component;
        component_var.uuid = Uuid.new();

        self.components.append(component_var) catch @panic("OOM");
        self.components_deinit_handles.append(.{ .ptr = component.ptr, .deinitalizer = def.destroy }) catch @panic("OOM");

        if (component_var.type_id == utils.typeId(MeshRenderer)) {
            self.scene.renderables.append(@ptrCast(@alignCast(component_var.ptr))) catch @panic("OOM");
        } else if (component_var.type_id == utils.typeId(Camera)) {
            if (self.scene.main_camera == null) {
                _ = self.ref();
                self.scene.main_camera = @ptrCast(@alignCast(component_var.ptr));
            }
        }
    }

    pub fn findChildren(self: *Self, obj: *Object) ?usize {
        for (self.children.items, 0..) |c, i| {
            if (c == obj) {
                return i;
            }
        }
        return null;
    }

    pub fn insertChildren(self: *Self, i: usize, obj: *Object) void {
        std.debug.assert(obj.parent != self);
        _ = obj.ref();
        if (obj.parent) |old_parent| {
            old_parent.removeChildren(obj);
        }
        obj.parent = self;
        self.children.insert(i, obj) catch @panic("OOM");
    }

    pub fn swapChildrens(self: *Self, i: usize, j: usize) void {
        std.debug.assert(i != j);
        const tmp = self.children.items[i];
        self.children.items[i] = self.children.items[j];
        self.children.items[j] = tmp;
    }

    pub inline fn addChildren(self: *Self, obj: *Object) void {
        self.insertChildren(self.children.items.len, obj);
    }

    pub fn removeChildren(self: *Self, obj: *Object) void {
        std.debug.assert(obj.parent == self);
        const index: usize = self.findChildren(obj) orelse @panic("not found");
        _ = self.children.orderedRemove(index);
        obj.parent = null;
        obj.deref();
    }

    pub fn getComponent(self: *Self, comptime C: type) ?*C {
        for (self.components.items) |comp| {
            if (comp.type_id == utils.typeId(C)) {
                return @as(*C, @ptrCast(@alignCast(comp.ptr)));
            }
        }
        return null;
    }

    pub fn translate(self: *Self, translation: Mat4) void {
        self.transform = self.transform.mul(translation);
        for (self.components) |component| {
            component.onTransformChange(self.transform);
        }
        for (self.children.items) |children| {
            children.setTransform(translation);
        }
    }

    pub fn bounds(self: *const Self) BoundingBox {
        var bb = BoundingBox{
            .mins = Vec3.scalar(std.math.floatMax(f32)),
            .maxs = Vec3.scalar(std.math.floatMin(f32)),
        };
        for (self.components.items) |component| {
            if (component.bounds) |b| {
                bb.accumulateBB(b(component.ptr));
            }
        }
        return bb.translate(self.transform.matrix);
    }

    pub fn jsonStringify(self: Self, jws: anytype) !void {
        return jws.write(self.uuid.urn());
    }

    pub fn jsonStringifyGraph(self: Self, jws: anytype) !void {
        try jws.beginObject();

        try jws.objectField("uuid");
        try jws.write(self.uuid.urn());

        try jws.objectField("name");
        try jws.write(self.name);

        try jws.objectField("transform");
        try jws.write(self.transform);

        try jws.objectField("parent");
        try jws.write(self.parent);

        // try jws.objectField("components");
        // try jws.write(self.components.items);

        try jws.objectField("children");
        try jws.beginArray();
        for (self.children.items) |child| {
            try child.jsonStringifyGraph(jws);
        }
        try jws.endArray();

        try jws.endObject();
    }

    pub fn jsonParseGraph(
        a: std.mem.Allocator,
        jrs: anytype,
        o: anytype,
        ctx: struct {
            scene: *Scene,
            ptrmap: *std.AutoHashMap(Uuid, *anyopaque),
        },
    ) !*Self {
        var tk = try jrs.next();
        if (tk != .object_begin) return error.UnexpectedEndOfInput;

        const result = try a.create(Object);
        result.* = .{
            .uuid = .{ .raw = 0 },
            .name = undefined,
            .transform = undefined,
            .children = std.ArrayList(*Object).init(a),
            .components = std.ArrayList(Component).init(a),
            .components_deinit_handles = std.ArrayList(ComponentDeinitializer).init(a),

            .scene = ctx.scene,
        };

        while (true) {
            tk = try jrs.nextAlloc(a, .alloc_if_needed);
            if (tk == .object_end) break;

            const field_name = switch (tk) {
                inline .string, .allocated_string => |slice| slice,
                else => {
                    std.debug.print("{}\n", .{tk});
                    return error.UnexpectedToken;
                },
            };

            if (std.mem.eql(u8, field_name, "uuid")) {
                result.uuid = try Uuid.jsonParse(a, jrs, o);
                try ctx.ptrmap.put(result.uuid, result);
            } else if (std.mem.eql(u8, field_name, "name")) {
                result.name = switch (try jrs.next()) {
                    inline .string => |slice| try a.dupeZ(u8, slice),
                    else => {
                        std.debug.print("{}\n", .{tk});
                        return error.UnexpectedToken;
                    },
                };
            } else if (std.mem.eql(u8, field_name, "transform")) {
                result.transform = try Transform.jsonParse(a, jrs, o);
            } else if (std.mem.eql(u8, field_name, "parent")) {
                if (try jrs.peekNextTokenType() == .null) {
                    _ = try jrs.next();
                    result.parent = null;
                    continue;
                }
                const parent_id = try Uuid.jsonParse(a, jrs, o);
                const ptr = ctx.ptrmap.get(parent_id);
                if (ptr) |p| {
                    result.parent = @as(*Self, @ptrCast(@alignCast(p)));
                    continue;
                }
                std.debug.print("Failed to resolve reference {s}", .{parent_id.urn()});
                return error.UnexpectedToken;
            } else if (std.mem.eql(u8, field_name, "children")) {
                std.debug.assert(try jrs.next() == .array_begin);
                if (result.uuid.raw == 0) {
                    return error.SyntaxError;
                }
                while (true) {
                    const peek = try jrs.peekNextTokenType();
                    if (peek == .array_end) {
                        _ = try jrs.next();
                        break;
                    }
                    const children = try Self.jsonParseGraph(a, jrs, o, ctx);
                    try result.children.append(children);
                }
            } else {
                try jrs.skipValue();
            }
        }

        return result;
    }
};

pub const Transform = struct {
    const Self = @This();

    matrix: Mat4,
    // after any change to this struct, the user should call `updateMatrices` method to reflect it correctly.
    raw: struct {
        position: Vec3,
        rotation: Vec3,
        scale: Vec3,
    },

    pub inline fn position(self: *Self) Vec3 {
        return self.raw.position;
    }

    pub inline fn rotation(self: *Self) Vec3 {
        return self.raw.rotation;
    }

    pub inline fn scale(self: *Self) Vec3 {
        return self.raw.scale;
    }

    pub inline fn setPosition(self: *Self, pos: Vec3) void {
        self.raw.position = pos;
    }

    pub inline fn setRotation(self: *Self) Vec3 {
        return self.raw.rotation;
    }

    pub inline fn setScale(self: *Self) Vec3 {
        return self.raw.scale;
    }

    pub fn fromMatrix(m: Mat4) Self {
        const parts = m.decompose();
        var self = Self{
            .matrix = undefined,
            .raw = .{
                .position = parts.translation,
                .rotation = parts.rotation.toEuler(),
                .scale = parts.scale,
            },
        };
        self.updateMatrices();
        return self;
    }

    pub inline fn matrix(self: *const Self) Mat4 {
        return Mat4.compose(self.position(), Quat.fromEuler(self.rotation()), self.scale());
    }

    pub inline fn updateMatrices(self: *Self) void {
        self.matrix = Mat4.compose(self.position(), Quat.fromEuler(self.rotation()), self.scale());
    }

    pub fn jsonStringify(self: Self, jws: anytype) !void {
        try jws.beginObject();

        try jws.objectField("position");
        try jws.write(self.raw.position);

        try jws.objectField("rotation");
        try jws.write(self.raw.rotation);

        try jws.objectField("scale");
        try jws.write(self.raw.scale);

        try jws.endObject();
    }

    pub fn jsonParse(a: std.mem.Allocator, jrs: anytype, o: anytype) !Self {
        var tk = try jrs.next();
        if (tk != .object_begin) return error.UnexpectedEndOfInput;

        var result = Self{
            .matrix = undefined,
            .raw = undefined,
        };

        while (true) {
            tk = try jrs.nextAlloc(a, .alloc_if_needed);
            if (tk == .object_end) break;

            const field_name = switch (tk) {
                inline .string, .allocated_string => |slice| slice,
                else => {
                    std.debug.print("{}\n", .{tk});
                    return error.UnexpectedToken;
                },
            };

            if (std.mem.eql(u8, field_name, "position")) {
                result.raw.position = try Vec3.jsonParse(a, jrs, o);
            } else if (std.mem.eql(u8, field_name, "rotation")) {
                result.raw.rotation = try Vec3.jsonParse(a, jrs, o);
            } else if (std.mem.eql(u8, field_name, "scale")) {
                result.raw.scale = try Vec3.jsonParse(a, jrs, o);
            } else {
                try jrs.skipValue();
            }
        }

        result.updateMatrices();

        return result;
    }
};

pub const Component = struct {
    type_id: usize,
    name: [:0]const u8,
    enable: bool = true,
    ptr: *anyopaque,
    uuid: Uuid = undefined,
    update: *const fn (self: *anyopaque, dt: f32) void = struct {
        fn noop(_: *anyopaque, _: f32) void {}
    }.noop,
    onTransformChange: *const fn (self: *anyopaque, transform: Mat4) void = struct {
        fn noop(_: *anyopaque, _: Mat4) void {}
    }.noop,
    bounds: ?*const fn (_: *anyopaque) BoundingBox = null,
    deinit: *const fn (_: *anyopaque) void = struct {
        fn noop(_: *anyopaque) void {}
    }.noop,
};

pub const ComponentDefinition = struct {
    type_id: usize,
    name: [:0]const u8,
    create_default: *const fn (allocator: std.mem.Allocator, obj: *Object) anyerror!Component,
    destroy: *const fn (allocator: std.mem.Allocator, ptr: *anyopaque) void,
    fromJson: *const fn (s: []const u8, ptr: *anyopaque) anyerror!void,
    toJson: *const fn (self: *anyopaque) []u8,
};
