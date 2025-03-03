const std = @import("std");

const Mat4 = @import("math3d.zig").Mat4;
const MeshRenderer = @import("VulkanEngine.zig").MeshRenderer;

pub const Scene = struct {
    const Self = @This();

    root: Object,
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
        self.root = Object.init(self, "root", Mat4.IDENTITY);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.renderables.deinit();
        self.root.deinit();
        for (self.live_object.items) |obj| {
            self.allocator.destroy(obj);
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
                break :blk &self.root;
            }
        };
        const obj = self.allocator.create(Object) catch @panic("OOM");
        self.live_object.append(obj) catch @panic("OOM");
        obj.* = Object.init(self, options.name, options.transform);
        parent.addChildren(obj);
        return obj;
    }
};

const ComponentDeinitializer = struct {
    ptr: *anyopaque,
    deinitalizer: *const fn (allocator: std.mem.Allocator, ptr: *anyopaque) void,
};

pub const Object = struct {
    const Self = @This();

    name: []const u8,
    transform: Mat4,
    parent: ?*Object = null,
    children: std.ArrayList(*Object),
    components: std.ArrayList(Component),
    components_deinit_handles: std.ArrayList(ComponentDeinitializer),
    scene: *Scene,

    pub fn init(scene: *Scene, name: []const u8, transform: Mat4) Object {
        return .{
            .name = name,
            .transform = transform,
            .children = std.ArrayList(*Object).init(scene.allocator),
            .components = std.ArrayList(Component).init(scene.allocator),
            .components_deinit_handles = std.ArrayList(ComponentDeinitializer).init(scene.allocator),

            .scene = scene,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.components.items) |component| {
            component.deinit();
        }
        self.components.deinit();
        for (self.components_deinit_handles.items) |handle| {
            handle.deinitalizer(self.scene.allocator, handle.ptr);
        }
        self.components_deinit_handles.deinit();
        for (self.children.items) |children| {
            children.deinit();
        }
        self.children.deinit();
    }

    pub fn addComponent(self: *Self, comptime ComponentType: type, init_options: @typeInfo(@TypeOf(ComponentType.init)).Fn.params[1].type.?) void {
        const component = self.scene.allocator.create(ComponentType) catch @panic("OOM");
        component.* = ComponentType.init(self, init_options);

        self.components.append(component.asComponent()) catch @panic("OOM");
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
        return obj.setParent(self);
    }

    pub fn setParent(self: *Self, parent: *Object) void {
        if (self.parent == parent) return;
        if (self.parent) |p| {
            var index: usize = 0;
            for (p.children.items, 0..) |c, i| {
                if (c == self) {
                    index = i;
                }
            }
            _ = p.children.swapRemove(index);
        }
        self.parent = parent;
        parent.children.append(self) catch @panic("OOM");
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
};

pub const Component = struct {
    update: *const fn (dt: f32) void = struct {
        fn noop(_: f32) void {}
    }.noop,
    onTransformChange: *const fn (transform: Mat4) void = struct {
        fn noop(_: Mat4) void {}
    }.noop,
    deinit: *const fn () void = struct {
        fn noop() void {}
    }.noop,
};
