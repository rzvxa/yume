const std = @import("std");

const Mat4 = @import("math3d.zig").Mat4;

const Scene = struct {
    const Self = @This();

    root: Object,
};

const Object = struct {
    name: [*c]const u8,
    transform: Mat4,
    children: std.ArrayList(Object),
    components: std.ArrayList(Component),

    pub fn init(allocator: std.mem.Allocator, transform: Mat4) Object {
        return .{
            .transform = transform,
            .children = std.ArrayList(Object).init(allocator),
            .components = std.ArrayList(Component).init(allocator),
        };
    }

    pub fn translate(self: *@This(), translation: Mat4) void {
        self.transform = self.transform.mul(translation);
        for (self.components) |component| {
            component.onTransformChange(self.transform);
        }
        for (self.children.items) |children| {
            children.setTransform(translation);
        }
    }
};

const Component = struct {
    update: fn (dt: f32) void = struct {
        inline fn noop(_: f32) void {}
    }.noop,
    onTransformChange: fn (transform: Mat4) void = struct {
        inline fn noop(_: Mat4) void {}
    }.noop,
};
