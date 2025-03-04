const std = @import("std");

const Uuid = @import("uuid.zig");
const Vec3 = @import("math3d.zig").Vec3;
const Mat4 = @import("math3d.zig").Mat4;
const MeshRenderer = @import("VulkanEngine.zig").MeshRenderer;
const BoundingBox = @import("mesh.zig").BoundingBox;

pub const Scene = struct {
    const Self = @This();

    root: *Object,
    renderables: std.ArrayList(*MeshRenderer),
    live_object: std.ArrayList(*Object),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .renderables = std.ArrayList(*MeshRenderer).init(allocator),
            .live_object = std.ArrayList(*Object).init(allocator),
            .root = undefined,
        };
        self.root = Object.create(self, "root", Mat4.IDENTITY) catch @panic("OOM");
        self.live_object.append(self.root.ref()) catch @panic("OOM");

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.renderables.deinit();
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

    pub fn fromJSON(allocator: std.mem.Allocator, json: []u8) Self {
        std.json.parseFromSlice(Self, allocator, json, .{});
    }

    pub fn newObject(self: *Scene, options: struct {
        name: []const u8 = "Object",
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
        const obj = Object.create(self, options.name, options.transform) catch @panic("OOM");
        self.live_object.append(obj) catch @panic("OOM");
        parent.addChildren(obj);
        return obj.ref();
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
    name: []const u8,
    transform: Mat4,
    parent: ?*Object = null,
    children: std.ArrayList(*Object),
    components: std.ArrayList(Component),
    components_deinit_handles: std.ArrayList(ComponentDeinitializer),
    scene: *Scene,

    pub fn create(scene: *Scene, name: []const u8, transform: Mat4) !*Object {
        const self = try scene.allocator.create(Self);
        self.* = .{
            .uuid = Uuid.new(),
            .name = name,
            .transform = transform,
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
        self.scene.allocator.destroy(self);
    }

    pub fn addComponent(self: *Self, comptime ComponentType: type, init_options: @typeInfo(@TypeOf(ComponentType.init)).Fn.params[1].type.?) void {
        const component = self.scene.allocator.create(ComponentType) catch @panic("OOM");
        component.* = ComponentType.init(self, init_options);

        var interface = component.asComponent();
        interface.uuid = Uuid.new();

        self.components.append(interface) catch @panic("OOM");
        const deinitializer = struct {
            fn f(allocator: std.mem.Allocator, ptr: *anyopaque) void {
                allocator.destroy(@as(*ComponentType, @ptrCast(@alignCast(ptr))));
            }
        };
        self.components_deinit_handles.append(.{ .ptr = component, .deinitalizer = deinitializer.f }) catch @panic("OOM");

        if (ComponentType == MeshRenderer) {
            self.scene.renderables.append(component) catch @panic("OOM");
        }
    }

    pub fn addChildren(self: *Self, obj: *Object) void {
        std.debug.assert(obj.parent != self);
        _ = obj.ref();
        if (obj.parent) |old_parent| {
            old_parent.removeChildren(obj);
        }
        obj.parent = self;
        self.children.append(obj) catch @panic("OOM");
    }

    pub fn removeChildren(self: *Self, obj: *Object) void {
        std.debug.assert(obj.parent == self);
        const index: usize = blk: {
            for (self.children.items, 0..) |c, i| {
                if (c == obj) {
                    break :blk i;
                }
            }
            @panic("not found?");
        };
        _ = self.children.orderedRemove(index);
        obj.parent = null;
        obj.deref();
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
        return bb.translate(self.transform);
    }
};

pub const Component = struct {
    type_id: u32,
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
