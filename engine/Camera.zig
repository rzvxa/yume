const std = @import("std");

const math3d = @import("math3d.zig");
const Vec2 = math3d.Vec2;
const Vec3 = math3d.Vec3;
const Vec4 = math3d.Vec4;
const Mat4 = math3d.Mat4;

pub const CameraKind = enum { perspective };
pub const PerspectiveOptions = struct {
    fovy_rad: f32,
    near: f32,
    far: f32,
};

pub const CameraOptions = union(CameraKind) { perspective: PerspectiveOptions };

const Self = @This();

opts: CameraOptions,

view: Mat4 = Mat4.make(Vec4.ZERO, Vec4.ZERO, Vec4.ZERO, Vec4.ZERO),
projection: Mat4 = Mat4.make(Vec4.ZERO, Vec4.ZERO, Vec4.ZERO, Vec4.ZERO),
view_projection: Mat4 = Mat4.make(Vec4.ZERO, Vec4.ZERO, Vec4.ZERO, Vec4.ZERO),

pub fn makePerspectiveCamera(opts: PerspectiveOptions) Self {
    return Self{ .opts = .{ .perspective = opts } };
}

pub fn updateTransformation(self: *Self, pos: Vec3, rot: Vec3, aspect: f32) void {
    switch (self.opts) {
        .perspective => self.updatePerspectiveTransformation(pos, rot, aspect),
    }
}

inline fn updatePerspectiveTransformation(self: *Self, pos: Vec3, rot: Vec3, aspect: f32) void {
    self.updatePerspectiveView(pos, rot);
    self.updatePerspectiveProjection(aspect);
    self.updatePerspectiveViewProjection();
}

inline fn updatePerspectiveView(self: *Self, pos: Vec3, rot: Vec3) void {
    // Create rotation matrices for pitch (X), yaw (Y), and roll (Z)
    const rot_x = Mat4.rotation(Vec3.make(1.0, 0.0, 0.0), rot.x);
    const rot_y = Mat4.rotation(Vec3.make(0.0, 1.0, 0.0), rot.y);
    const rot_z = Mat4.rotation(Vec3.make(0.0, 0.0, 1.0), rot.z);

    const g = Vec3.make(-pos.x, -pos.y, pos.z);
    self.view = rot_x.mul(rot_y).mul(rot_z).mul(Mat4.translation(g));
}

inline fn updatePerspectiveProjection(self: *Self, aspect: f32) void {
    const opts = self.opts.perspective;
    self.projection = Mat4.perspective(opts.fovy_rad, aspect, opts.near, opts.far);
    self.projection.j.y *= -1.0;
}

inline fn updatePerspectiveViewProjection(self: *Self) void {
    self.view_projection = self.projection.mul(self.view);
}
