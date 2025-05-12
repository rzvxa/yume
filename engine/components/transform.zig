const std = @import("std");
const ecs = @import("../ecs.zig");
const Vec3 = @import("../math3d.zig").Vec3;
const Quat = @import("../math3d.zig").Quat;
const Mat4 = @import("../math3d.zig").Mat4;
const Dynamic = @import("../serialization/dynamic.zig").Dynamic;

pub const LocalTransform = extern struct {
    const Self = @This();

    matrix: Mat4,
    dirty: bool = true,

    pub inline fn decompose(self: *const Self) Mat4.Decomposed {
        return self.matrix.decompose() catch Mat4.Decomposed.IDENTITY;
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
        return try Mat4.serialize(&self.matrix, allocator);
    }

    pub fn deserialize(self: *Self, matrix: *const Dynamic, allocator: std.mem.Allocator) !void {
        try Mat4.deserialize(&self.matrix, matrix, allocator);
    }

    pub fn onAdd(iter: *ecs.Iterator) void {
        for (0..@intCast(iter.inner.count)) |i| {
            const entity = iter.inner.entities[i];
            const world = iter.realWorld();
            world.set(entity, WorldTransform, .{ .matrix = Mat4.IDENTITY, .dirty = true });
        }
    }

    pub fn onSet(iter: *ecs.Iterator) void {
        var wts = ecs.field(iter, Self, 0) orelse return;
        for (0..wts.len) |i| {
            wts[i].dirty = true;
        }
    }

    pub fn onRemove(iter: *ecs.Iterator) void {
        for (0..@intCast(iter.inner.count)) |i| {
            const entity = iter.inner.entities[i];
            const world = iter.realWorld();
            world.remove(entity, WorldTransform);
        }
    }
};

pub const WorldTransform = extern struct {
    const Self = @This();

    matrix: Mat4,
    dirty: bool = true,

    pub inline fn decompose(self: *const Self) Mat4.Decomposed {
        return self.matrix.decompose() catch Mat4.Decomposed.IDENTITY;
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
        return try Mat4.serialize(&self.matrix, allocator);
    }

    pub fn deserialize(self: *Self, matrix: *const Dynamic, allocator: std.mem.Allocator) !void {
        try Mat4.deserialize(&self.matrix, matrix, allocator);
    }

    pub fn onSet(iter: *ecs.Iterator) void {
        var wts = ecs.field(iter, Self, 0) orelse return;
        for (0..wts.len) |i| {
            wts[i].dirty = true;
        }
    }
};
