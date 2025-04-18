const std = @import("std");

const Dynamic = @import("serialization/dynamic.zig").Dynamic;
const Uuid = @import("uuid.zig").Uuid;
const Vec3 = @import("math3d.zig").Vec3;
const Mat4 = @import("math3d.zig").Mat4;
const Quat = @import("math3d.zig").Quat;
const utils = @import("utils.zig");
const Camera = @import("components/camera.zig").Camera;
const BoundingBox = @import("components/mesh.zig").BoundingBox;

pub const Scene = struct {
    const Self = @This();

    root: *Object,
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);

        var arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        const a = arena.allocator();

        self.* = .{
            .arena = arena,
            .allocator = a,
            .root = undefined,
        };
        self.root = Object.create(self, try a.dupeZ(u8, "root")) catch @panic("OOM");

        return self;
    }

    pub fn deinit(self: *Self) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
        allocator.destroy(self);
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
        errdefer allocator.destroy(result);

        var arena = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();

        result.* = Self{
            .arena = arena,
            .allocator = a,
            .root = undefined,
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

            if (std.mem.eql(u8, field_name, "root")) {
                var ptrmap = std.AutoHashMap(Uuid, *anyopaque).init(a);
                defer ptrmap.deinit();
                result.root = try Object.jsonParseGraph(a, jrs, o, .{
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
        self.stack.appendAssumeCapacity(root);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
    }

    pub fn next(self: *Self) !?*Object {
        if (self.stack.items.len == 0) return null;

        const obj = self.stack.pop();
        for (obj.children.items) |o| {
            try self.stack.append(o);
        }
        return obj;
    }
};

const Object = struct {
    const Self = @This();

    uuid: Uuid,
    name: [:0]u8,
    parent: ?*Object = null,
    children: std.ArrayList(*Object),
    components: std.StringArrayHashMap(Component),
    scene: *Scene,

    fn create(scene: *Scene, name: [:0]u8) !*Object {
        const self = try scene.allocator.create(Self);
        self.* = .{
            .uuid = Uuid.new(),
            .name = name,
            .children = std.ArrayList(*Object).init(scene.allocator),
            .components = std.StringArrayHashMap(Component).init(scene.allocator),

            .scene = scene,
        };
        return self;
    }

    pub fn findChildren(self: *Self, obj: *Object) ?usize {
        for (self.children.items, 0..) |c, i| {
            if (c == obj) {
                return i;
            }
        }
        return null;
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
            .name = try a.allocSentinel(u8, 0, 0),
            .children = std.ArrayList(*Object).init(a),
            .components = std.StringArrayHashMap(Component).init(a),

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
            } else if (std.mem.eql(u8, field_name, "components")) {
                const dyn = try Dynamic.jsonParse(a, jrs, o);
                switch (dyn.type) {
                    .object => {
                        for (0..dyn.count) |i| {
                            const field = dyn.value.object[i];
                            try result.components.put(std.mem.span(field.key), field.value);
                        }
                    },
                    else => return error.UnexpectedToken,
                }
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

    pub inline fn position(self: *const Self) Vec3 {
        return self.raw.position;
    }

    pub inline fn rotation(self: *const Self) Vec3 {
        return self.raw.rotation;
    }

    pub inline fn scale(self: *const Self) Vec3 {
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

    pub inline fn getMatrix(self: *const Self) Mat4 {
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

pub const Component = Dynamic;
