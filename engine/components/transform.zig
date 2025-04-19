const std = @import("std");
const ecs = @import("../ecs.zig");
const Vec3 = @import("../math3d.zig").Vec3;
const Mat4 = @import("../math3d.zig").Mat4;
const Dynamic = @import("../serialization/dynamic.zig").Dynamic;

pub const Position = extern struct {
    value: Vec3 = Vec3.scalar(0),

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        return try Vec3.serialize(&self.value, allocator);
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, allocator: std.mem.Allocator) !void {
        try Vec3.deserialize(&self.value, value, allocator);
    }
};

pub const Rotation = extern struct {
    value: Vec3 = Vec3.scalar(0),

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        return try Vec3.serialize(&self.value, allocator);
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, allocator: std.mem.Allocator) !void {
        try Vec3.deserialize(&self.value, value, allocator);
    }
};

pub const Scale = extern struct {
    value: Vec3 = Vec3.scalar(1),

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        return try Vec3.serialize(&self.value, allocator);
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, allocator: std.mem.Allocator) !void {
        try Vec3.deserialize(&self.value, value, allocator);
    }
};

pub const TransformMatrix = extern struct {
    value: Mat4,

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        return try Mat4.serialize(&self.value, allocator);
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, allocator: std.mem.Allocator) !void {
        try Mat4.deserialize(&self.value, value, allocator);
    }
};
