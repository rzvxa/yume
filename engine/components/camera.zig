const std = @import("std");

const ecs = @import("../ecs.zig");
const GameApp = @import("../GameApp.zig");
const Component = @import("../scene.zig").Component;
const typeId = @import("../utils.zig").typeId;
const Dynamic = @import("../serialization/dynamic.zig").Dynamic;
const math3d = @import("../math3d.zig");
const Vec2 = math3d.Vec2;
const Vec3 = math3d.Vec3;
const Vec4 = math3d.Vec4;
const Mat4 = math3d.Mat4;

pub const CameraKind = enum(u8) {
    pub const perspective_name = "Perspective";
    pub const orthographic_name = "Orthographic";

    perspective,
    orthographic,

    pub fn typeName(self: CameraKind) []const u8 {
        return switch (self) {
            .perspective => perspective_name,
            .orthographic => orthographic_name,
        };
    }
};
pub const PerspectiveOptions = extern struct {
    fovy_rad: f32 = std.math.degreesToRadians(75),
    near: f32 = 0.1,
    far: f32 = 200,
};
pub const OrthographicOptions = extern struct {
    left: f32 = -10,
    right: f32 = 10,
    bottom: f32 = -10,
    top: f32 = 10,
    near: f32 = 0.1,
    far: f32 = 200,
};

pub const CameraOptions = extern struct {
    kind: CameraKind,
    data: extern union {
        perspective: PerspectiveOptions,
        orthographic: OrthographicOptions,
    },

    pub fn typeName(self: CameraOptions) []const u8 {
        return self.kind.typeName();
    }
};

pub const Camera = extern struct {
    const Self = @This();

    opts: CameraOptions,

    view: Mat4 = Mat4.IDENTITY,
    projection: Mat4 = Mat4.make(Vec4.ZERO, Vec4.ZERO, Vec4.ZERO, Vec4.ZERO),
    view_projection: Mat4 = Mat4.make(Vec4.ZERO, Vec4.ZERO, Vec4.ZERO, Vec4.ZERO),

    pub fn editorIcon() [*:0]const u8 {
        return "editor://icons/camera.png";
    }

    pub fn editorBillboard() [*:0]const u8 {
        return "editor://icons/camera.png";
    }

    pub fn default(self: *Camera, _: ecs.Entity, _: *GameApp) callconv(.C) bool {
        self.* = .{
            .opts = .{
                .kind = .perspective,
                .data = .{
                    .perspective = .{
                        .fovy_rad = std.math.degreesToRadians(75),
                        .far = 200,
                        .near = 0.1,
                    },
                },
            },
        };
        return true;
    }

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        switch (self.opts.kind) {
            .perspective => {
                const fields = try allocator.alloc(Dynamic.Field, 4);
                fields[0] = .{
                    .key = try allocator.dupeZ(u8, "type"),
                    .value = .{ .type = .string, .value = .{ .string = try allocator.dupeZ(u8, "perspective") } },
                };
                fields[1] = .{
                    .key = try allocator.dupeZ(u8, "fovy_rad"),
                    .value = .{ .type = .number, .value = .{ .number = self.opts.data.perspective.fovy_rad } },
                };
                fields[2] = .{
                    .key = try allocator.dupeZ(u8, "near"),
                    .value = .{ .type = .number, .value = .{ .number = self.opts.data.perspective.near } },
                };
                fields[3] = .{
                    .key = try allocator.dupeZ(u8, "far"),
                    .value = .{ .type = .number, .value = .{ .number = self.opts.data.perspective.far } },
                };
                return .{ .type = .object, .value = .{ .object = .{ .items = fields.ptr, .len = fields.len } } };
            },
            .orthographic => @panic("unimplemented orthographic camera serialization"),
        }
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, _: std.mem.Allocator) !void {
        const obj = try value.expectObject();
        const kind: CameraKind = blk: {
            const s = std.mem.span(try (try obj.expectField("type")).value.expectString());
            if (std.mem.eql(u8, s, "perspective")) {
                break :blk .perspective;
            } else if (std.mem.eql(u8, s, "orthographic")) {
                break :blk .orthographic;
            }
            return error.InvalidCameraType;
        };

        switch (kind) {
            .perspective => self.* = .{
                .opts = .{
                    .kind = kind,
                    .data = .{
                        .perspective = .{
                            .fovy_rad = try (try obj.expectField("fovy_rad")).value.expectNumber(),
                            .near = try (try obj.expectField("near")).value.expectNumber(),
                            .far = try (try obj.expectField("far")).value.expectNumber(),
                        },
                    },
                },
            },
            .orthographic => @panic("unimplemented orthographic camera deserialization"),
        }
    }

    pub fn makePerspectiveCamera(opts: PerspectiveOptions) Self {
        return Self{ .opts = .{ .kind = .perspective, .data = .{ .perspective = opts } } };
    }

    pub fn makeOrthographicCamera(opts: OrthographicOptions) Self {
        return Self{ .opts = .{ .kind = .orthographic, .data = .{ .orthographic = opts } } };
    }

    pub fn updateMatrices(self: *Self, pos: Vec3, rot: Vec3, aspect: f32) void {
        switch (self.opts.kind) {
            .perspective => self.updatePerspectiveMatrices(pos, rot, aspect),
            .orthographic => self.updateOrthographicMatrices(pos, rot, aspect),
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
        const rot_x = Mat4.rotation(Vec3.make(1.0, 0.0, 0.0), std.math.degreesToRadians(rot.x));
        const rot_y = Mat4.rotation(Vec3.make(0.0, 1.0, 0.0), std.math.degreesToRadians(rot.y));
        const rot_z = Mat4.rotation(Vec3.make(0.0, 0.0, 1.0), std.math.degreesToRadians(rot.z));

        const g = Vec3.make(-pos.x, -pos.y, -pos.z);
        self.view = rot_x.mul(rot_y).mul(rot_z).mul(Mat4.translation(g));
    }

    pub inline fn updatePerspectiveProjection(self: *Self, aspect: f32) void {
        const opts = self.opts.data.perspective;
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

        const g = Vec3.make(-pos.x, -pos.y, -pos.z);
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

    pub inline fn updateViewProjection(self: *Self) void {
        self.view_projection = self.projection.mul(self.view);
    }

    fn destroy(allocator: std.mem.Allocator, ptr: *Self) void {
        allocator.destroy(ptr);
    }

    fn fromJson(s: []const u8, ptr: *Self) !void {
        _ = s;
        _ = ptr;
    }

    fn toJson(self: *Self) []u8 {
        _ = self;
        return &[_]u8{};
    }

    pub fn asComponent(self: *Self) Component {
        return .{
            .type_id = typeId(Self),
            .name = "Camera",
            .ptr = self,
        };
    }
};
