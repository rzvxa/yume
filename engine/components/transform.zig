const std = @import("std");
const ecs = @import("../ecs.zig");
const Vec3 = @import("../math3d.zig").Vec3;
const Quat = @import("../math3d.zig").Quat;
const Mat4 = @import("../math3d.zig").Mat4;
const Dynamic = @import("../serialization/dynamic.zig").Dynamic;

pub const Transform = extern struct {
    const Self = @This();

    value: Mat4,

    pub inline fn decompose(self: *const Self) Mat4.Decomposed {
        return self.value.decompose() catch Mat4.Decomposed.IDENTITY;
    }

    pub inline fn position(self: *const Self) Vec3 {
        return self.decompose().translation;
    }

    pub inline fn rotation(self: *const Self) Quat {
        return self.decompose().rotation;
    }

    pub inline fn scale(self: *const Self) Vec3 {
        return self.decompose().scale;
    }

    pub fn serialize(self: *const Self, allocator: std.mem.Allocator) !Dynamic {
        return try Mat4.serialize(&self.value, allocator);
    }

    pub fn deserialize(self: *Self, value: *const Dynamic, allocator: std.mem.Allocator) !void {
        try Mat4.deserialize(&self.value, value, allocator);
    }
};
