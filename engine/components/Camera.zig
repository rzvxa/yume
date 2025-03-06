const std = @import("std");

const Object = @import("../scene.zig").Object;
const Component = @import("../scene.zig").Component;
const typeId = @import("../utils.zig").typeId;
const math3d = @import("../math3d.zig");
const Vec2 = math3d.Vec2;
const Vec3 = math3d.Vec3;
const Vec4 = math3d.Vec4;
const Mat4 = math3d.Mat4;

pub const CameraKind = enum { perspective, orthographic };
pub const PerspectiveOptions = struct {
    fovy_rad: f32,
    near: f32,
    far: f32,
};
pub const OrthographicOptions = struct {
    left: f32,
    right: f32,
    bottom: f32,
    top: f32,
    near: f32,
    far: f32,
};

pub const CameraOptions = union(CameraKind) {
    perspective: PerspectiveOptions,
    orthographic: OrthographicOptions,
};

const Self = @This();

object: *Object = undefined,
opts: CameraOptions,

view: Mat4 = Mat4.make(Vec4.ZERO, Vec4.ZERO, Vec4.ZERO, Vec4.ZERO),
projection: Mat4 = Mat4.make(Vec4.ZERO, Vec4.ZERO, Vec4.ZERO, Vec4.ZERO),
view_projection: Mat4 = Mat4.make(Vec4.ZERO, Vec4.ZERO, Vec4.ZERO, Vec4.ZERO),

pub fn init(object: *Object, opts: CameraOptions) Self {
    var self = switch (opts) {
        .perspective => makePerspectiveCamera(opts.perspective),
        .orthographic => makeOrthographicCamera(opts.orthographic),
    };
    self.object = object;
    return self;
}

pub fn makePerspectiveCamera(opts: PerspectiveOptions) Self {
    return Self{ .opts = .{ .perspective = opts } };
}

pub fn makeOrthographicCamera(opts: OrthographicOptions) Self {
    return Self{ .opts = .{ .orthographic = opts } };
}

pub fn updateMatrices(self: *Self, pos: Vec3, rot: Vec3, aspect: f32) void {
    switch (self.opts) {
        .perspective => self.updatePerspectiveMatrices(pos, rot, aspect),
        .orthographic => self.updatePerspectiveMatrices(pos, rot, aspect),
    }
}

pub fn viewDirection(position: Vec3, direction: Vec3, up: Vec3) Mat4 {
    const w = direction.normalized();
    const u = w.cross(up).normalized();
    const v = w.cross(u);

    var mat = Mat4.scalar(1);
    mat.i.x = u.x;
    mat.j.x = u.y;
    mat.k.x = u.z;
    mat.i.y = v.x;
    mat.j.y = v.y;
    mat.k.y = v.z;
    mat.i.z = w.x;
    mat.j.z = w.y;
    mat.k.z = w.z;
    mat.t.x = -u.dot(position);
    mat.t.y = -v.dot(position);
    mat.t.z = -w.dot(position);
    return mat;
}

pub fn viewTarget(position: Vec3, target: Vec3, up: Vec3) Mat4 {
    const direction = target.sub(position);
    // TODO
    // assert(!glm::all(glm::lessThan(glm::abs(direction), glm::vec3(std::numeric_limits<float>::epsilon()))));
    return Self.viewDirection(position, direction, up);
}

pub fn viewYXZ(position: Vec3, rot: Vec3) Mat4 {
    const c3 = @cos(rot.z);
    const s3 = @sin(rot.z);
    const c2 = @cos(rot.x);
    const s2 = @sin(rot.x);
    const c1 = @cos(rot.y);
    const s1 = @sin(rot.y);
    const u = Vec3.make((c1 * c3 + s1 * s2 * s3), (c2 * s3), (c1 * s2 * s3 - c3 * s1));
    const v = Vec3.make((c3 * s1 * s2 - c1 * s3), (c2 * c3), (c1 * c3 * s2 + s1 * s3));
    const w = Vec3.make((c2 * s1), (-s2), (c1 * c2));

    var mat = Mat4.scalar(1);
    mat.i.x = u.x;
    mat.j.x = u.y;
    mat.k.x = u.z;
    mat.i.y = v.x;
    mat.j.y = v.y;
    mat.k.y = v.z;
    mat.i.z = w.x;
    mat.j.z = w.y;
    mat.k.z = w.z;
    mat.t.x = -u.dot(position);
    mat.t.y = -v.dot(position);
    mat.t.z = -w.dot(position);
    return mat;
}

pub fn viewXYZ(position: Vec3, rot: Vec3) Mat4 {
    const c1 = @cos(rot.x); // Pitch
    const s1 = @sin(rot.x);
    const c2 = @cos(rot.y); // Yaw
    const s2 = @sin(rot.y);
    const c3 = @cos(rot.z); // Roll
    const s3 = @sin(rot.z);

    // Basis vectors using XYZ order (Pitch-Yaw-Roll)
    const u = Vec3.make((c2 * c3), (c1 * s3 + s1 * s2 * c3), (s1 * s3 - c1 * s2 * c3));
    const v = Vec3.make((-c2 * s3), (c1 * c3 - s1 * s2 * s3), (s1 * c3 + c1 * s2 * s3));
    const w = Vec3.make((s2), (-s1 * c2), (c1 * c2));

    var mat = Mat4.scalar(1);
    mat.i.x = u.x;
    mat.j.x = u.y;
    mat.k.x = u.z;
    mat.i.y = v.x;
    mat.j.y = v.y;
    mat.k.y = v.z;
    mat.i.z = w.x;
    mat.j.z = w.y;
    mat.k.z = w.z;
    mat.t.x = -u.dot(position);
    mat.t.y = -v.dot(position);
    mat.t.z = -w.dot(position);

    return mat;
}

inline fn updatePerspectiveMatrices(self: *Self, pos: Vec3, rot: Vec3, aspect: f32) void {
    self.updatePerspectiveView(pos, rot);
    self.updatePerspectiveProjection(aspect);
    self.updateViewProjection();
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
    self.projection.unnamed[1][1] *= -1.0;
}

inline fn updateOrthographicMatrices(self: *Self, pos: Vec3, rot: Vec3, aspect: f32) void {
    self.updateOrthographicView(pos, rot);
    self.updateOrthographicProjection(aspect);
    self.updateViewProjection();
}

inline fn updateOrthographicView(self: *Self, pos: Vec3, rot: Vec3) void {
    // Create rotation matrices for pitch (X), yaw (Y), and roll (Z)
    const rot_x = Mat4.rotation(Vec3.make(1.0, 0.0, 0.0), rot.x);
    const rot_y = Mat4.rotation(Vec3.make(0.0, 1.0, 0.0), rot.y);
    const rot_z = Mat4.rotation(Vec3.make(0.0, 0.0, 1.0), rot.z);

    const g = Vec3.make(-pos.x, -pos.y, pos.z);
    self.view = rot_x.mul(rot_y).mul(rot_z).mul(Mat4.translation(g));
}

inline fn updateOrthographicProjection(self: *Self, aspect: f32) void {
    _ = aspect;
    // const opts = self.opts.perspective;
    // self.projection = Mat4.perspective(opts.fovy_rad, aspect, opts.near, opts.far);
    // self.projection = Mat4.orthographic(0, 1, 0, 1, 0, 200);
    self.projection = Mat4.orthographic(-10.0, 10.0, -10.0, 10.0, 0, 200);
    // self.projection.unnamed[1][1] *= -1.0;
}

inline fn updateViewProjection(self: *Self) void {
    self.view_projection = self.projection.mul(self.view);
}

pub fn asComponent(self: *Self) Component {
    return .{
        .type_id = typeId(Self),
        .name = "Camera",
        .ptr = self,
    };
}
