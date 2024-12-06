const yume = @import("../root.zig");
const Mat4 = yume.Mat4;
const Vec3 = yume.Vec3;
const BoolVec3 = yume.BoolVec3;
const assert = @import("../assert.zig").assert;
const std = @import("std");

const Self = @This();

const epsilon = std.math.floatEps(f32);
projection_matrix: Mat4 = Mat4.as(1),
view_matrix: Mat4 = Mat4.as(1),

pub fn setOrthographicProjection(self: *Self, left: f32, right: f32, top: f32, bottom: f32, near: f32, far: f32) void {
    self.projection_matrix = Mat4.as(1);
    self.projection_matrix.setAt(0, 0, 2 / (right - left));
    self.projection_matrix.setAt(1, 1, 2 / (bottom - top));
    self.projection_matrix.setAt(2, 2, 1 / (far - near));
    self.projection_matrix.setAt(3, 0, -(right + left) / (right - left));
    self.projection_matrix.setAt(3, 1, -(bottom + top) / (bottom - top));
    self.projection_matrix.setAt(3, 2, -near / (far - near));
}

pub fn setPrespectiveProjection(self: *Self, fovy: f32, aspect: f32, near: f32, far: f32) void {
    assert(@abs(aspect - epsilon) > 0, "aspect ratio can't be 0.", .{});
    const tanHalfFovy = @tan(fovy / 2);
    self.projection_matrix = Mat4.as(1);
    self.projection_matrix.setAt(0, 0, 1 / (aspect * tanHalfFovy));
    self.projection_matrix.setAt(1, 1, 1 / (tanHalfFovy));
    self.projection_matrix.setAt(2, 2, far / (far - near));
    self.projection_matrix.setAt(2, 3, 1);
    self.projection_matrix.setAt(3, 2, -(far * near) / (far - near));
}

pub fn setViewDirection(self: *Self, position: Vec3, direction: Vec3, up: Vec3) void {
    const w = direction.normalize();
    const u = Vec3.cross(w, up).normalize();
    const v = Vec3.cross(w, u);

    self.view_matrix = Mat4.as(1);
    self.view_matrix.setAt(0, 0, u.x);
    self.view_matrix.setAt(1, 0, u.y);
    self.view_matrix.setAt(2, 0, u.z);
    self.view_matrix.setAt(0, 1, v.x);
    self.view_matrix.setAt(1, 1, v.y);
    self.view_matrix.setAt(2, 1, v.z);
    self.view_matrix.setAt(0, 2, w.x);
    self.view_matrix.setAt(1, 2, w.y);
    self.view_matrix.setAt(2, 2, w.z);
    self.view_matrix.setAt(3, 0, -Vec3.dot(u, position));
    self.view_matrix.setAt(3, 1, -Vec3.dot(v, position));
    self.view_matrix.setAt(3, 2, -Vec3.dot(w, position));
}

pub fn setViewTarget(self: *Self, position: Vec3, target: Vec3, up: Vec3) void {
    const direction = target.sub(position);
    assert(
        !BoolVec3.all(Vec3.lessThan(Vec3.abs(direction), Vec3.as(epsilon))),
        "`position` and `target` can't be the same.",
        .{},
    );
    self.setViewDirection(position, direction, up);
}

pub fn setViewYXZ(self: *Self, position: Vec3, rotation: Vec3) void {
    const c3 = @cos(rotation.z);
    const s3 = @sin(rotation.z);
    const c2 = @cos(rotation.x);
    const s2 = @sin(rotation.x);
    const c1 = @cos(rotation.y);
    const s1 = @sin(rotation.y);
    const u = Vec3.new((c1 * c3 + s1 * s2 * s3), (c2 * s3), (c1 * s2 * s3 - c3 * s1));
    const v = Vec3.new((c3 * s1 * s2 - c1 * s3), (c2 * c3), (c1 * c3 * s2 + s1 * s3));
    const w = Vec3.new((c2 * s1), (-s2), (c1 * c2));
    self.view_matrix = Mat4.as(1);
    self.view_matrix.setAt(0, 0, u.x);
    self.view_matrix.setAt(1, 0, u.y);
    self.view_matrix.setAt(2, 0, u.z);
    self.view_matrix.setAt(0, 1, v.x);
    self.view_matrix.setAt(1, 1, v.y);
    self.view_matrix.setAt(2, 1, v.z);
    self.view_matrix.setAt(0, 2, w.x);
    self.view_matrix.setAt(1, 2, w.y);
    self.view_matrix.setAt(2, 2, w.z);
    self.view_matrix.setAt(3, 0, -Vec3.dot(u, position));
    self.view_matrix.setAt(3, 1, -Vec3.dot(v, position));
    self.view_matrix.setAt(3, 2, -Vec3.dot(w, position));
}
