const std = @import("std");
const Dynamic = @import("serialization/dynamic.zig").Dynamic;

pub const epsilon = std.math.floatEps(f32);

pub const Vec2 = extern struct {
    const Self = @This();
    x: f32,
    y: f32,

    pub inline fn make(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub inline fn mulf(self: Self, other: f32) Self {
        return make(self.x * other, self.y * other);
    }

    pub inline fn scalar(n: f32) Vec2 {
        return .{ .x = n, .y = n };
    }

    pub inline fn squaredLen(self: Self) f32 {
        return self.x * self.x + self.y * self.y;
    }

    pub inline fn len(self: Self) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub inline fn add(self: Self, other: Self) Self {
        return make(self.x - other.x, self.y - other.y);
    }

    pub inline fn sub(self: Self, other: Self) Self {
        return make(self.x - other.x, self.y - other.y);
    }

    pub fn lerp(a: Self, b: Self, t: f32) Self {
        return make(
            std.math.lerp(a.x, b.x, t),
            std.math.lerp(a.y, b.y, t),
        );
    }

    pub inline fn toVec3(self: Vec2, z: f32) Vec3 {
        return .{ .x = self.x, .y = self.y, .z = z };
    }

    pub inline fn fromArray(xy: [2]f32) Self {
        return @as(*const Self, @ptrCast(&xy)).*;
    }

    pub inline fn toArray(self: Self) [2]f32 {
        return @as(*const [2]f32, @ptrCast(&self)).*;
    }
};

pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    const Self = @This();

    pub const UP = make(0.0, 1.0, 0.0);

    pub inline fn make(x: f32, y: f32, z: f32) Self {
        return .{ .x = x, .y = y, .z = z };
    }

    pub inline fn fromArray(xyz: [3]f32) Self {
        return @as(*const Self, @ptrCast(&xyz)).*;
    }

    pub inline fn scalar(n: f32) Self {
        return make(n, n, n);
    }

    pub inline fn squaredLen(self: Self) f32 {
        return self.x * self.x + self.y * self.y + self.z * self.z;
    }

    pub inline fn len(self: Self) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    pub inline fn add(self: Self, other: Self) Self {
        return make(self.x + other.x, self.y + other.y, self.z + other.z);
    }

    pub inline fn sub(self: Self, other: Self) Self {
        return make(self.x - other.x, self.y - other.y, self.z - other.z);
    }

    // this method doesn't exists mathematically but is a convenient name for a operation,
    // we are multiplying components of 2 vectors
    pub inline fn mul(self: Self, other: Self) Self {
        return make(self.x * other.x, self.y * other.y, self.z * other.z);
    }

    pub inline fn mulf(self: Self, other: f32) Self {
        return make(self.x * other, self.y * other, self.z * other);
    }

    // this method doesn't exists mathematically but is a convenient name for a operation,
    // we are dividing components of 2 vectors
    pub inline fn div(self: Self, other: Self) Self {
        return make(self.x / other.x, self.y / other.x, self.z / other.x);
    }

    pub inline fn divf(self: Self, other: f32) Self {
        return make(self.x / other, self.y / other, self.z / other);
    }

    pub inline fn normalized(self: Self) Self {
        const l = self.len();
        if (l > 0) {
            return self.divf(l);
        } else {
            return Self.scalar(0);
        }
    }

    pub inline fn dot(a: Self, b: Self) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub inline fn cross(a: Self, b: Self) Self {
        return make(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x,
        );
    }

    pub inline fn toVec4(self: Self, w: f32) Vec4 {
        return Vec4.make(self.x, self.y, self.z, w);
    }

    pub inline fn toArray(self: Self) [3]f32 {
        return @as(*const [3]f32, @ptrCast(&self)).*;
    }

    pub fn getComponent(v: Vec3, index: usize) f32 {
        return switch (index) {
            0 => v.x,
            1 => v.y,
            2 => v.z,
            else => unreachable,
        };
    }

    pub fn combine(v: Vec3, other: Vec3, scaleV: f32, scaleOther: f32) Vec3 {
        return Vec3.make(v.x * scaleV + other.x * scaleOther, v.y * scaleV + other.y * scaleOther, v.z * scaleV + other.z * scaleOther);
    }

    /// Computes the Euclidean distance between two points.
    pub fn distanceTo(self: Vec3, other: Vec3) f32 {
        return self.sub(other).len();
    }

    pub fn lerp(a: Self, b: Self, t: f32) Self {
        return make(
            std.math.lerp(a.x, b.x, t),
            std.math.lerp(a.y, b.y, t),
            std.math.lerp(a.z, b.z, t),
        );
    }

    pub fn jsonStringify(self: Self, jws: anytype) !void {
        try jws.beginArray();

        try jws.write(self.x);
        try jws.write(self.y);
        try jws.write(self.z);

        try jws.endArray();
    }

    pub fn jsonParse(a: std.mem.Allocator, jrs: anytype, _: anytype) !Self {
        var tk = try jrs.next();
        if (tk != .array_begin) return error.UnexpectedEndOfInput;

        var xyz = [3]f32{ 0, 0, 0 };

        for (0..3) |i| {
            tk = try jrs.nextAlloc(a, .alloc_if_needed);
            if (tk == .array_end) return error.UnexpectedEndOfInput;

            xyz[i] = switch (tk) {
                inline .number, .allocated_number => |slice| std.fmt.parseFloat(f32, slice) catch return error.SyntaxError,
                else => {
                    return error.UnexpectedToken;
                },
            };
        }

        tk = try jrs.next();
        std.debug.assert(tk == .array_end);

        return fromArray(xyz);
    }

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        const elements = try allocator.alloc(Dynamic, 3);
        elements[0] = .{ .type = .number, .value = .{ .number = self.x } };
        elements[1] = .{ .type = .number, .value = .{ .number = self.y } };
        elements[2] = .{ .type = .number, .value = .{ .number = self.z } };
        return .{
            .type = .array,
            .value = .{ .array = .{ .items = elements.ptr, .len = elements.len } },
        };
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, _: std.mem.Allocator) !void {
        const array = try value.expectArray();
        if (array.len != 3) {
            return error.UnexpectedValue;
        }

        self.* = Vec3.make(
            try array.items[0].expect(.number),
            try array.items[1].expect(.number),
            try array.items[2].expect(.number),
        );
    }
};

pub const Vec4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    // Those are not real thing, however, they match my preference for 3d coordinates:
    // - x is right;
    // - y is forward;
    // - z is up.
    // The coordinate system is right-handed.
    // This allows to use x,y coordinates as a 2d vector on the floor plane (so to speak).
    pub const UP = make(0.0, 0.0, 1.0, 0.0);
    pub const FORWARD = make(0.0, 1.0, 0.0, 0.0);
    pub const RIGHT = make(1.0, 0.0, 0.0, 0.0);

    const Self = @This();

    pub inline fn make(x: f32, y: f32, z: f32, w: f32) Self {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }

    pub inline fn scalar(n: f32) Self {
        return make(n, n, n, n);
    }

    pub fn add(self: Self, other: Self) Self {
        // The result is going to be a point if either of the operands is a point.
        return make(
            self.x + other.x,
            self.y + other.y,
            self.z + other.z,
            if (self.w > 0 or other.w > 0) 1.0 else 0.0,
        );
    }

    pub fn mulMat4(self: Self, mat: Mat4) Mat4 {
        const m = mat.unnamed;
        return make(
            self.x * m[0][0] + self.y * m[0][1] + self.z * m[0][2] + self.w * m[0][3],
            self.x * m[1][0] + self.y * m[1][1] + self.z * m[1][2] + self.w * m[1][3],
            self.x * m[2][0] + self.y * m[2][1] + self.z * m[2][2] + self.w * m[2][3],
            self.x * m[3][0] + self.y * m[3][1] + self.z * m[3][2] + self.w * m[3][3],
        );
    }

    pub fn nomalized(self: Self) Self {
        return self.toVec3().normalized().toVec4(self.w);
    }

    pub fn toVec3(self: Self) Vec3 {
        return Vec3.make(self.x, self.y, self.z);
    }

    pub inline fn fromArray(xyzw: [4]f32) Self {
        return @as(*const Self, @ptrCast(&xyzw)).*;
    }

    pub inline fn toArray(self: Self) [4]f32 {
        return @as(*const [4]f32, @ptrCast(&self)).*;
    }

    pub inline fn dot(a: Self, b: Self) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    }

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        const elements = try allocator.alloc(Dynamic, 4);
        elements[0] = .{ .type = .number, .value = .{ .number = self.x } };
        elements[1] = .{ .type = .number, .value = .{ .number = self.y } };
        elements[2] = .{ .type = .number, .value = .{ .number = self.z } };
        elements[3] = .{ .type = .number, .value = .{ .number = self.w } };
        return .{
            .type = .array,
            .value = .{ .array = .{ .items = elements.ptr, .len = elements.len } },
        };
    }

    pub fn deserialize(self: *@This(), value: *const @import("serialization/dynamic.zig").Dynamic, _: std.mem.Allocator) !void {
        const array = try value.expectArray();
        if (array.len != 4) {
            return error.UnexpectedValue;
        }

        self.* = Vec4.make(
            try array.items[0].expect(.number),
            try array.items[1].expect(.number),
            try array.items[2].expect(.number),
            try array.items[3].expect(.number),
        );
    }

    pub fn jsonStringify(self: Self, jws: anytype) !void {
        try jws.beginArray();

        try jws.write(self.x);
        try jws.write(self.y);
        try jws.write(self.z);
        try jws.write(self.w);

        try jws.endArray();
    }

    pub fn jsonParse(a: std.mem.Allocator, jrs: anytype, _: anytype) !Self {
        var tk = try jrs.next();
        if (tk != .array_begin) return error.UnexpectedEndOfInput;

        var xyzw = [4]f32{ 0, 0, 0, 0 };

        for (0..4) |i| {
            tk = try jrs.nextAlloc(a, .alloc_if_needed);
            if (tk == .array_end) return error.UnexpectedEndOfInput;

            xyzw[i] = switch (tk) {
                inline .number, .allocated_number => |slice| std.fmt.parseFloat(f32, slice) catch return error.SyntaxError,
                else => {
                    return error.UnexpectedToken;
                },
            };
        }

        tk = try jrs.next();
        std.debug.assert(tk == .array_end);

        return fromArray(xyzw);
    }
};

pub const Quat = extern struct {
    pub const BasisVectors = struct {
        right: Vec3,
        up: Vec3,
        forward: Vec3,
    };
    const Self = @This();

    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub const IDENTITY: Self = make(0, 0, 0, 1);

    pub inline fn make(x: f32, y: f32, z: f32, w: f32) Self {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }

    pub fn fromAxisAngle(axis: Vec3, angle: f32) Quat {
        const half_angle = angle / 2.0;
        const sin_half_angle = @sin(half_angle);
        return Quat{
            .w = @cos(half_angle),
            .x = axis.x * sin_half_angle,
            .y = axis.y * sin_half_angle,
            .z = axis.z * sin_half_angle,
        };
    }

    pub fn mul(self: Quat, other: Quat) Quat {
        return Quat{
            .w = self.w * other.w - self.x * other.x - self.y * other.y - self.z * other.z,
            .x = self.w * other.x + self.x * other.w + self.y * other.z - self.z * other.y,
            .y = self.w * other.y - self.x * other.z + self.y * other.w + self.z * other.x,
            .z = self.w * other.z + self.x * other.y - self.y * other.x + self.z * other.w,
        };
    }

    pub fn mulVec3(self: Self, v: Vec3) Vec3 {
        const q_vec = Vec3.make(self.x, self.y, self.z);
        const uv = Vec3.cross(q_vec, v);
        const uuv = Vec3.cross(q_vec, uv);
        return v.add((uv.mulf(2 * self.w)).add(uuv.mulf(2)));
    }

    pub fn normalized(self: Self) Self {
        const length = @sqrt(self.w * self.w + self.x * self.x + self.y * self.y + self.z * self.z);
        return make(
            self.x / length,
            self.y / length,
            self.z / length,
            self.w / length,
        );
    }

    pub fn toVec4(self: Self) Vec4 {
        return @as(*const Vec4, @ptrCast(&self)).*;
    }

    pub fn toEuler(self: Self) Vec3 {
        const half_pi: f32 = std.math.pi / 2.0;
        var euler = Vec3.scalar(0);

        // Roll (x-axis rotation)
        const sinr_cosp = 2 * (self.w * self.x + self.y * self.z);
        const cosr_cosp = 1 - 2 * (self.x * self.x + self.y * self.y);
        euler.x = std.math.atan2(sinr_cosp, cosr_cosp);

        // Pitch (y-axis rotation)
        const sinp = 2 * (self.w * self.y - self.z * self.x);
        if (@abs(sinp) >= 1) {
            euler.y = std.math.copysign(half_pi, sinp); // Use 90 degrees if out of range
        } else {
            euler.y = std.math.asin(sinp);
        }

        // Yaw (z-axis rotation)
        const siny_cosp = 2 * (self.w * self.z + self.x * self.y);
        const cosy_cosp = 1 - 2 * (self.y * self.y + self.z * self.z);
        euler.z = std.math.atan2(siny_cosp, cosy_cosp);

        // Convert to degrees
        return euler.mulf(180.0).divf(std.math.pi);
    }

    pub fn fromEuler(euler: Vec3) Quat {
        const half_to_rad = 0.5 * std.math.pi / 180.0;

        const roll = euler.x * half_to_rad;
        const pitch = euler.y * half_to_rad;
        const yaw = euler.z * half_to_rad;

        const cr = @cos(roll);
        const sr = @sin(roll);
        const cp = @cos(pitch);
        const sp = @sin(pitch);
        const cy = @cos(yaw);
        const sy = @sin(yaw);

        return Self{
            .w = cr * cp * cy + sr * sp * sy,
            .x = sr * cp * cy - cr * sp * sy,
            .y = cr * sp * cy + sr * cp * sy,
            .z = cr * cp * sy - sr * sp * cy,
        };
    }

    pub fn fromMat4(m: Mat4) Self {
        const trace = m.unnamed[0][0] + m.unnamed[1][1] + m.unnamed[2][2];
        var q = Self.make(0, 0, 0, 0);

        if (trace > 0) {
            const s = @sqrt(trace + 1.0) * 2;
            q.w = 0.25 * s;
            q.x = (m.unnamed[2][1] - m.unnamed[1][2]) / s;
            q.y = (m.unnamed[0][2] - m.unnamed[2][0]) / s;
            q.z = (m.unnamed[1][0] - m.unnamed[0][1]) / s;
        } else if (m.unnamed[0][0] > m.unnamed[1][1] and m.unnamed[0][0] > m.unnamed[2][2]) {
            const s = @sqrt(1.0 + m.unnamed[0][0] - m.unnamed[1][1] - m.unnamed[2][2]) * 2;
            q.w = (m.unnamed[2][1] - m.unnamed[1][2]) / s;
            q.x = 0.25 * s;
            q.y = (m.unnamed[0][1] + m.unnamed[1][0]) / s;
            q.z = (m.unnamed[0][2] + m.unnamed[2][0]) / s;
        } else if (m.unnamed[1][1] > m.unnamed[2][2]) {
            const s = @sqrt(1.0 + m.unnamed[1][1] - m.unnamed[0][0] - m.unnamed[2][2]) * 2;
            q.w = (m.unnamed[0][2] - m.unnamed[2][0]) / s;
            q.x = (m.unnamed[0][1] + m.unnamed[1][0]) / s;
            q.y = 0.25 * s;
            q.z = (m.unnamed[1][2] + m.unnamed[2][1]) / s;
        } else {
            const s = @sqrt(1.0 + m.unnamed[2][2] - m.unnamed[0][0] - m.unnamed[1][1]) * 2;
            q.w = (m.unnamed[1][0] - m.unnamed[0][1]) / s;
            q.x = (m.unnamed[0][2] + m.unnamed[2][0]) / s;
            q.y = (m.unnamed[1][2] + m.unnamed[2][1]) / s;
            q.z = 0.25 * s;
        }

        return q;
    }

    pub fn toBasisVectors(quat: Quat) BasisVectors {
        const x = quat.x;
        const y = quat.y;
        const z = quat.z;
        const w = quat.w;

        const xx = x * x;
        const yy = y * y;
        const zz = z * z;
        const xy = x * y;
        const xz = x * z;
        const yz = y * z;
        const wx = w * x;
        const wy = w * y;
        const wz = w * z;

        const right = Vec3.make(1.0 - 2.0 * (yy + zz), 2.0 * (xy + wz), 2.0 * (xz - wy));

        const up = Vec3.make(2.0 * (xy - wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz + wx));

        const forward = Vec3.make(2.0 * (xz + wy), 2.0 * (yz - wx), 1.0 - 2.0 * (xx + yy));

        return BasisVectors{
            .right = right.normalized(),
            .up = up.normalized(),
            .forward = forward.normalized(),
        };
    }
};

pub const Mat4 = extern union {
    pub const Decomposed = struct {
        translation: Vec3,
        rotation: Quat,
        scale: Vec3,

        pub const IDENTITY: Decomposed = .{
            .translation = Vec3.scalar(0),
            .rotation = Quat.IDENTITY,
            .scale = Vec3.scalar(1),
        };
    };
    named: extern struct {
        i: Vec4,
        j: Vec4,
        k: Vec4,
        t: Vec4,
    },
    unnamed: [4][4]f32,
    values: [16]f32,
    vec4: [4]Vec4,

    const Self = @This();

    pub const IDENTITY: Self = .{ .values = .{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    } };

    pub inline fn make(i: Vec4, j: Vec4, k: Vec4, t: Vec4) Self {
        return .{ .vec4 = .{ i, j, k, t } };
    }

    pub inline fn scalar(n: f32) Self {
        return make(
            Vec4.scalar(n),
            Vec4.scalar(n),
            Vec4.scalar(n),
            Vec4.scalar(n),
        );
    }

    /// Returns the transpose of the input matrix
    pub fn transposed(self: Self) Self {
        return make(
            Vec4.make(self.named.i.x, self.named.j.x, self.named.k.x, self.named.t.x),
            Vec4.make(self.named.i.y, self.named.j.y, self.named.k.y, self.named.t.y),
            Vec4.make(self.named.i.z, self.named.j.z, self.named.k.z, self.named.t.z),
            Vec4.make(self.named.i.w, self.named.j.w, self.named.k.w, self.named.t.w),
        );
    }

    pub fn mul(ma: Self, mb: Self) Self {
        return make(
            Vec4.make(
                ma.named.i.x * mb.named.i.x + ma.named.j.x * mb.named.i.y + ma.named.k.x * mb.named.i.z + ma.named.t.x * mb.named.i.w,
                ma.named.i.y * mb.named.i.x + ma.named.j.y * mb.named.i.y + ma.named.k.y * mb.named.i.z + ma.named.t.y * mb.named.i.w,
                ma.named.i.z * mb.named.i.x + ma.named.j.z * mb.named.i.y + ma.named.k.z * mb.named.i.z + ma.named.t.z * mb.named.i.w,
                ma.named.i.w * mb.named.i.x + ma.named.j.w * mb.named.i.y + ma.named.k.w * mb.named.i.z + ma.named.t.w * mb.named.i.w,
            ),
            Vec4.make(
                ma.named.i.x * mb.named.j.x + ma.named.j.x * mb.named.j.y + ma.named.k.x * mb.named.j.z + ma.named.t.x * mb.named.j.w,
                ma.named.i.y * mb.named.j.x + ma.named.j.y * mb.named.j.y + ma.named.k.y * mb.named.j.z + ma.named.t.y * mb.named.j.w,
                ma.named.i.z * mb.named.j.x + ma.named.j.z * mb.named.j.y + ma.named.k.z * mb.named.j.z + ma.named.t.z * mb.named.j.w,
                ma.named.i.w * mb.named.j.x + ma.named.j.w * mb.named.j.y + ma.named.k.w * mb.named.j.z + ma.named.t.w * mb.named.j.w,
            ),
            Vec4.make(
                ma.named.i.x * mb.named.k.x + ma.named.j.x * mb.named.k.y + ma.named.k.x * mb.named.k.z + ma.named.t.x * mb.named.k.w,
                ma.named.i.y * mb.named.k.x + ma.named.j.y * mb.named.k.y + ma.named.k.y * mb.named.k.z + ma.named.t.y * mb.named.k.w,
                ma.named.i.z * mb.named.k.x + ma.named.j.z * mb.named.k.y + ma.named.k.z * mb.named.k.z + ma.named.t.z * mb.named.k.w,
                ma.named.i.w * mb.named.k.x + ma.named.j.w * mb.named.k.y + ma.named.k.w * mb.named.k.z + ma.named.t.w * mb.named.k.w,
            ),
            Vec4.make(
                ma.named.i.x * mb.named.t.x + ma.named.j.x * mb.named.t.y + ma.named.k.x * mb.named.t.z + ma.named.t.x * mb.named.t.w,
                ma.named.i.y * mb.named.t.x + ma.named.j.y * mb.named.t.y + ma.named.k.y * mb.named.t.z + ma.named.t.y * mb.named.t.w,
                ma.named.i.z * mb.named.t.x + ma.named.j.z * mb.named.t.y + ma.named.k.z * mb.named.t.z + ma.named.t.z * mb.named.t.w,
                ma.named.i.w * mb.named.t.x + ma.named.j.w * mb.named.t.y + ma.named.k.w * mb.named.t.z + ma.named.t.w * mb.named.t.w,
            ),
        );
    }

    pub fn mulVec4(self: Self, v: Vec4) Vec4 {
        const m = self.unnamed;
        return Vec4.make(
            v.x * m[0][0] + v.y * m[1][0] + v.z * m[2][0] + v.w * m[3][0],
            v.x * m[0][1] + v.y * m[1][1] + v.z * m[2][1] + v.w * m[3][1],
            v.x * m[0][2] + v.y * m[1][2] + v.z * m[2][2] + v.w * m[3][2],
            v.x * m[0][3] + v.y * m[1][3] + v.z * m[2][3] + v.w * m[3][3],
        );
    }

    pub inline fn mulVec3(self: Self, v: Vec3) Vec3 {
        const r = self.mulVec4(v.toVec4(1));
        return Vec3.make(r.x / r.w, r.y / r.w, r.z / r.w);
    }

    /// Create a translation matrix
    pub fn translation(v: Vec3) Mat4 {
        return make(
            Vec4.make(1.0, 0.0, 0.0, 0.0),
            Vec4.make(0.0, 1.0, 0.0, 0.0),
            Vec4.make(0.0, 0.0, 1.0, 0.0),
            v.toVec4(1),
        );
    }

    /// Returns a new matrix obtained by translating the input one.
    pub fn translate(self: Self, v: Vec3) Self {
        return make(
            self.named.i,
            self.named.j,
            self.named.k,
            self.named.t.add(v.toVec4(0)),
        );
    }

    /// Create a perspective projection matrix
    /// The result matrix is for a right-handed, zero to one, clipping space.
    pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) Mat4 {
        std.debug.assert(@abs(aspect) > 0.0001);
        const f = 1.0 / @tan(fovy_rad / 2.0);

        return make(
            Vec4.make(f / aspect, 0.0, 0.0, 0.0),
            Vec4.make(0.0, f, 0.0, 0.0),
            Vec4.make(0.0, 0.0, far / (near - far), -1.0),
            Vec4.make(0.0, 0.0, -(far * near) / (far - near), 0.0),
        );
    }

    pub fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
        return make(Vec4.make(
            2 / (right - left),
            0,
            0,
            0,
        ), Vec4.make(
            0,
            2 / (bottom - top),
            0,
            0,
        ), Vec4.make(
            0,
            0,
            1 / (near - far),
            0,
        ), Vec4.make(
            -(right + left) / (right - left),
            -(bottom + top) / (bottom - top),
            near / (near - far),
            1,
        ));
    }

    /// Create a rotation matrix around an arbitrary axis.
    // TODO: Add a faster version that assume the axis is normalized.
    pub fn rotation(axis: Vec3, angle_rad: f32) Mat4 {
        const c = @cos(angle_rad);
        const s = @sin(angle_rad);
        const t = 1.0 - c;

        const sqr_norm = axis.squaredLen();
        if (sqr_norm == 0.0) {
            return Mat4.IDENTITY;
        } else if (@abs(sqr_norm - 1.0) > 0.0001) {
            const norm = @sqrt(sqr_norm);
            return rotation(axis.divf(norm), angle_rad);
        }

        const x = axis.x;
        const y = axis.y;
        const z = axis.z;

        return make(
            Vec4.make(x * x * t + c, y * x * t + z * s, z * x * t - y * s, 0.0),
            Vec4.make(x * y * t - z * s, y * y * t + c, z * y * t + x * s, 0.0),
            Vec4.make(x * z * t + y * s, y * z * t - x * s, z * z * t + c, 0.0),
            Vec4.make(0.0, 0.0, 0.0, 1.0),
        );
    }

    ///Rotates a matrix around an arbitrary axis.
    // OPTIMIZE: We can work out the math to create the matrix directly.
    pub fn rotate(m: Mat4, axis: Vec3, angle_rad: f32) Mat4 {
        return mul(rotation(axis, angle_rad), m);
    }

    pub fn scale(v: Vec3) Mat4 {
        return make(
            Vec4.make(v.x, 0.0, 0.0, 0.0),
            Vec4.make(0.0, v.y, 0.0, 0.0),
            Vec4.make(0.0, 0.0, v.z, 0.0),
            Vec4.make(0.0, 0.0, 0.0, 1.0),
        );
    }

    pub fn fromQuat(quat: Quat) Mat4 {
        const x = quat.x;
        const y = quat.y;
        const z = quat.z;
        const w = quat.w;

        const xx = x * x;
        const yy = y * y;
        const zz = z * z;
        const xy = x * y;
        const xz = x * z;
        const yz = y * z;
        const wx = w * x;
        const wy = w * y;
        const wz = w * z;

        return Mat4.make(
            Vec4.make(1.0 - 2.0 * (yy + zz), 2.0 * (xy + wz), 2.0 * (xz - wy), 0.0),
            Vec4.make(2.0 * (xy - wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz + wx), 0.0),
            Vec4.make(2.0 * (xz + wy), 2.0 * (yz - wx), 1.0 - 2.0 * (xx + yy), 0.0),
            Vec4.make(0.0, 0.0, 0.0, 1.0),
        );
    }

    // calculate the determinant of the given matrix
    pub fn determinant(m: Mat4) f32 {
        var det: f32 = 0;
        for (0..3) |r| {
            det = det + (m.unnamed[0][r] *
                (m.unnamed[1][(r + 1) % 3] * m.unnamed[2][(r + 2) % 3] -
                m.unnamed[1][(r + 2) % 3] * m.unnamed[2][(r + 1) % 3]));
        }
        return det;
    }

    // Returns the inverse matrix. It will return an error if determinant is zero.
    pub fn inverse(self: Mat4) error{DeterminantZero}!Mat4 {
        // based on http://www.euclideanspace.com/maths/algebra/matrix/functions/inverse/fourD/index.htm
        const n11 = self.values[0];
        const n21 = self.values[1];
        const n31 = self.values[2];
        const n41 = self.values[3];
        const n12 = self.values[4];
        const n22 = self.values[5];
        const n32 = self.values[6];
        const n42 = self.values[7];
        const n13 = self.values[8];
        const n23 = self.values[9];
        const n33 = self.values[10];
        const n43 = self.values[11];
        const n14 = self.values[12];
        const n24 = self.values[13];
        const n34 = self.values[14];
        const n44 = self.values[15];

        const t11 = n23 * n34 * n42 - n24 * n33 * n42 + n24 * n32 * n43 - n22 * n34 * n43 - n23 * n32 * n44 + n22 * n33 * n44;
        const t12 = n14 * n33 * n42 - n13 * n34 * n42 - n14 * n32 * n43 + n12 * n34 * n43 + n13 * n32 * n44 - n12 * n33 * n44;
        const t13 = n13 * n24 * n42 - n14 * n23 * n42 + n14 * n22 * n43 - n12 * n24 * n43 - n13 * n22 * n44 + n12 * n23 * n44;
        const t14 = n14 * n23 * n32 - n13 * n24 * n32 - n14 * n22 * n33 + n12 * n24 * n33 + n13 * n22 * n34 - n12 * n23 * n34;

        const det = n11 * t11 + n21 * t12 + n31 * t13 + n41 * t14;

        if (det == 0) return error.DeterminantZero;

        const det_inv = 1 / det;

        return .{ .values = .{
            t11 * det_inv,
            (n24 * n33 * n41 - n23 * n34 * n41 - n24 * n31 * n43 + n21 * n34 * n43 + n23 * n31 * n44 - n21 * n33 * n44) * det_inv,
            (n22 * n34 * n41 - n24 * n32 * n41 + n24 * n31 * n42 - n21 * n34 * n42 - n22 * n31 * n44 + n21 * n32 * n44) * det_inv,
            (n23 * n32 * n41 - n22 * n33 * n41 - n23 * n31 * n42 + n21 * n33 * n42 + n22 * n31 * n43 - n21 * n32 * n43) * det_inv,

            t12 * det_inv,
            (n13 * n34 * n41 - n14 * n33 * n41 + n14 * n31 * n43 - n11 * n34 * n43 - n13 * n31 * n44 + n11 * n33 * n44) * det_inv,
            (n14 * n32 * n41 - n12 * n34 * n41 - n14 * n31 * n42 + n11 * n34 * n42 + n12 * n31 * n44 - n11 * n32 * n44) * det_inv,
            (n12 * n33 * n41 - n13 * n32 * n41 + n13 * n31 * n42 - n11 * n33 * n42 - n12 * n31 * n43 + n11 * n32 * n43) * det_inv,

            t13 * det_inv,
            (n14 * n23 * n41 - n13 * n24 * n41 - n14 * n21 * n43 + n11 * n24 * n43 + n13 * n21 * n44 - n11 * n23 * n44) * det_inv,
            (n12 * n24 * n41 - n14 * n22 * n41 + n14 * n21 * n42 - n11 * n24 * n42 - n12 * n21 * n44 + n11 * n22 * n44) * det_inv,
            (n13 * n22 * n41 - n12 * n23 * n41 - n13 * n21 * n42 + n11 * n23 * n42 + n12 * n21 * n43 - n11 * n22 * n43) * det_inv,

            t14 * det_inv,
            (n13 * n24 * n31 - n14 * n23 * n31 + n14 * n21 * n33 - n11 * n24 * n33 - n13 * n21 * n34 + n11 * n23 * n34) * det_inv,
            (n14 * n22 * n31 - n12 * n24 * n31 - n14 * n21 * n32 + n11 * n24 * n32 + n12 * n21 * n34 - n11 * n22 * n34) * det_inv,
            (n12 * n23 * n31 - n13 * n22 * n31 + n13 * n21 * n32 - n11 * n23 * n32 - n12 * n21 * n33 + n11 * n22 * n33) * det_inv,
        } };
    }

    pub fn compose(translation_vec: Vec3, rotation_quat: Quat, scale_vec: Vec3) Mat4 {
        const scale_mat = Mat4.scale(scale_vec);
        const rotation_mat = Mat4.fromQuat(rotation_quat);
        const translation_mat = Mat4.translation(translation_vec);

        return translation_mat.mul(rotation_mat).mul(scale_mat);
    }

    pub inline fn recompose(decomposed: Decomposed) Mat4 {
        return Mat4.compose(decomposed.translation, decomposed.rotation, decomposed.scale);
    }

    pub fn decompose(self: Self) !Decomposed {
        var m = self;

        // Normalize the matrix.
        if (epsilonEql(m.unnamed[3][3], 0.0)) {
            return error.InvalidMatrix;
        }
        for (0..4) |i| {
            for (0..4) |j| {
                m.unnamed[i][j] /= m.unnamed[3][3];
            }
        }

        // perspectiveMatrix is used for solving perspective and for
        // testing the singularity of the upper 3x3 component.
        var perspectiveMatrix = m;
        for (0..3) |i| {
            perspectiveMatrix.unnamed[i][3] = 0;
        }
        perspectiveMatrix.unnamed[3][3] = 1;

        if (epsilonEql(determinant3x3(perspectiveMatrix), 0)) {
            return error.InvalidMatrix;
        }

        var per: Vec4 = Vec4.make(0, 0, 0, 1);
        if (epsilonNotEql(m.unnamed[0][3], 0) or
            epsilonNotEql(m.unnamed[1][3], 0) or
            epsilonNotEql(m.unnamed[2][3], 0))
        {
            // Build the right-hand side vector.
            const rhs = Vec4.make(m.unnamed[0][3], m.unnamed[1][3], m.unnamed[2][3], m.unnamed[3][3]);
            // Solve the equation by inverting perspectiveMatrix.
            const inversePerspective: Mat4 = inverse(perspectiveMatrix) catch @panic("inverse err");
            var transposedInverse: Mat4 = transposed(inversePerspective);
            per = transposedInverse.mulVec4(rhs);

            // Clear the perspective partition.
            m.unnamed[0][3] = 0.0;
            m.unnamed[1][3] = 0.0;
            m.unnamed[2][3] = 0.0;
            m.unnamed[3][3] = 1.0;
        } else {
            per = Vec4.make(0.0, 0.0, 0.0, 1.0);
        }

        // Extract translation (assumed stored in the 4th row).
        const tran: Vec3 = m.vec4[3].toVec3();
        m.vec4[3] = Vec4.make(0.0, 0.0, 0.0, m.vec4[3].w);

        // Extract rows as 3-vectors (upper 3x3).
        var row: [3]Vec3 = undefined;
        for (0..3) |i| {
            row[i] = Vec3.make(m.unnamed[i][0], m.unnamed[i][1], m.unnamed[i][2]);
        }

        // Compute X scale factor and normalize the first row.
        var sc: Vec3 = undefined;
        sc.x = row[0].len();
        row[0] = row[0].normalized();

        // Compute XY shear factor and make 2nd row orthogonal to 1st.
        var skew: Vec3 = undefined;
        skew.z = row[0].dot(row[1]);
        row[1] = Vec3.combine(row[1], row[0], 1.0, -skew.z);

        // Compute Y scale and normalize 2nd row.
        sc.y = row[1].len();
        if (epsilonEql(sc.y, 0)) return error.InvalidMatrix;
        row[1] = row[1].normalized();
        skew.z /= sc.y;

        // Compute XZ and YZ shears; orthogonalize 3rd row.
        skew.y = row[0].dot(row[2]);
        row[2] = Vec3.combine(row[2], row[0], 1.0, -skew.y);
        skew.x = row[1].dot(row[2]);
        row[2] = Vec3.combine(row[2], row[1], 1.0, -skew.x);

        // Compute Z scale and normalize 3rd row.
        sc.z = row[2].len();
        if (epsilonEql(sc.z, 0)) return error.InvalidMatrix;
        row[2] = row[2].normalized();
        skew.y /= sc.z;
        skew.x /= sc.z;

        // If the determinant is negative, we must invert one row.
        const pdum3: Vec3 = row[1].cross(row[2]);
        if (row[0].dot(pdum3) < 0.0) {
            sc.x *= -1.0;
            sc.y *= -1.0;
            sc.z *= -1.0;
            row[0] = row[0].mulf(-1);
            row[1] = row[1].mulf(-1);
            row[2] = row[2].mulf(-1);
        }

        // Extract the rotation as a quaternion.
        var orientation: Quat = undefined;
        const trace: f32 = row[0].x + row[1].y + row[2].z;
        if (trace > 0.0) {
            var root = std.math.sqrt(trace + 1.0);
            orientation.w = 0.5 * root;
            root = 0.5 / root;
            orientation.x = root * (row[1].z - row[2].y);
            orientation.y = root * (row[2].x - row[0].z);
            orientation.z = root * (row[0].y - row[1].x);
        } else {
            // Find the major diagonal element to determine the quaternion.
            const Next: [3]usize = .{ 1, 2, 0 };
            var i: usize = 0;
            if (row[1].y > row[0].x) {
                i = 1;
            }
            if (row[2].getComponent(2) > row[i].getComponent(i)) {
                i = 2;
            }
            const j = Next[i];
            const k = Next[j];

            var root = std.math.sqrt(row[i].getComponent(i) - row[j].getComponent(j) - row[k].getComponent(k) + 1.0);
            switch (i) {
                0 => orientation.x = 0.5 * root,
                1 => orientation.y = 0.5 * root,
                2 => orientation.z = 0.5 * root,
                else => {},
            }
            root = 0.5 / root;
            if (i == 0) {
                orientation.y = root * (row[0].getComponent(1) + row[1].getComponent(0));
                orientation.z = root * (row[0].getComponent(2) + row[2].getComponent(0));
            } else if (i == 1) {
                orientation.x = root * (row[0].getComponent(1) + row[1].getComponent(0));
                orientation.z = root * (row[1].getComponent(2) + row[2].getComponent(1));
            } else {
                orientation.x = root * (row[0].getComponent(2) + row[2].getComponent(0));
                orientation.y = root * (row[1].getComponent(2) + row[2].getComponent(1));
            }
            if (i == 0) {
                orientation.w = root * (row[1].getComponent(2) - row[2].getComponent(1));
            } else if (i == 1) {
                orientation.w = root * (row[2].getComponent(0) - row[0].getComponent(2));
            } else {
                orientation.w = root * (row[0].getComponent(1) - row[1].getComponent(0));
            }
        }

        return Decomposed{
            .translation = tran,
            .rotation = orientation,
            .scale = sc,
            // .skew = skew,
            // .perspective = perspective,
        };
    }

    // compute the determinant of the upper 3x3 part of a Mat4.
    pub fn determinant3x3(m: Mat4) f32 {
        return m.unnamed[0][0] * (m.unnamed[1][1] * m.unnamed[2][2] - m.unnamed[1][2] * m.unnamed[2][1]) -
            m.unnamed[0][1] * (m.unnamed[1][0] * m.unnamed[2][2] - m.unnamed[1][2] * m.unnamed[2][0]) +
            m.unnamed[0][2] * (m.unnamed[1][0] * m.unnamed[2][1] - m.unnamed[1][1] * m.unnamed[2][0]);
    }

    // create a look at view
    pub fn lookAt(eye: Vec3, at: Vec3, up: Vec3) Mat4 {
        var x: Vec3 = undefined;
        var y: Vec3 = undefined;
        var z: Vec3 = undefined;
        var tmp: Vec3 = undefined;

        // Compute the direction vector `Z` (from eye to at) and normalize it
        tmp = Vec3.make(eye.x - at.x, eye.y - at.y, eye.z - at.z);
        z = tmp.normalized();

        // Normalize the up vector `Y`
        y = up.normalized();

        // Compute the right vector `X` as the cross product of `Y` and `Z`
        tmp = y.cross(z);
        x = tmp.normalized();

        // Recalculate the true up vector `Y` as the cross product of `Z` and `X`
        tmp = z.cross(x);
        y = tmp.normalized();

        // Create the LookAt matrix
        const m16: Mat4 = Mat4.make(
            Vec4.make(x.x, y.x, z.x, 0.0),
            Vec4.make(x.y, y.y, z.y, 0.0),
            Vec4.make(x.z, y.z, z.z, 0.0),
            Vec4.make(-x.dot(eye), -y.dot(eye), -z.dot(eye), 1.0),
        );

        return m16;
    }

    // imprecise, doesn't use epsilon
    pub fn eql(rhs: *const Self, lhs: *const Self) bool {
        return std.mem.eql(f32, &rhs.values, &lhs.values);
    }

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        const elements = try allocator.alloc(Dynamic, 4);
        elements[0] = try Vec4.serialize(&self.vec4[0], allocator);
        elements[1] = try Vec4.serialize(&self.vec4[1], allocator);
        elements[2] = try Vec4.serialize(&self.vec4[2], allocator);
        elements[3] = try Vec4.serialize(&self.vec4[3], allocator);
        return .{
            .type = .array,
            .value = .{ .array = .{ .items = elements.ptr, .len = elements.len } },
        };
    }

    pub fn deserialize(self: *@This(), value: *const @import("serialization/dynamic.zig").Dynamic, allocator: std.mem.Allocator) !void {
        const array = try value.expectArray();
        if (array.len != 4) {
            return error.UnexpectedValue;
        }

        try Vec4.deserialize(&self.vec4[0], &array.items[0], allocator);
        try Vec4.deserialize(&self.vec4[1], &array.items[1], allocator);
        try Vec4.deserialize(&self.vec4[2], &array.items[2], allocator);
        try Vec4.deserialize(&self.vec4[3], &array.items[3], allocator);
    }
};

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const Vec2U = extern struct {
    const Self = @This();
    x: u32,
    y: u32,

    pub inline fn make(x: u32, y: u32) Vec2U {
        return .{ .x = x, .y = y };
    }

    pub inline fn muli(self: Self, other: u32) Self {
        return make(self.x * other, self.y * other);
    }

    pub inline fn scalar(n: u32) Vec2U {
        return .{ .x = n, .y = n };
    }

    pub inline fn squaredLen(self: Self) f32 {
        return self.x * self.x + self.y * self.y;
    }

    pub inline fn len(self: Self) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub inline fn add(self: Self, other: Self) Self {
        return make(self.x - other.x, self.y - other.y);
    }

    pub inline fn sub(self: Self, other: Self) Self {
        return make(self.x - other.x, self.y - other.y);
    }

    pub fn lerp(a: Self, b: Self, t: f32) Self {
        return make(
            std.math.lerp(a.x, b.x, t),
            std.math.lerp(a.y, b.y, t),
        );
    }

    pub inline fn fromArray(xy: [2]u32) Self {
        return @as(*const Self, @ptrCast(&xy)).*;
    }

    pub inline fn toArray(self: Self) [2]u32 {
        return @as(*const [2]u32, @ptrCast(&self)).*;
    }

    pub inline fn toVec2(self: Self) Vec2 {
        return Vec2.make(@floatFromInt(self.x), @floatFromInt(self.y));
    }
};

pub fn epsilonEql(a: f32, b: f32) bool {
    return @abs(a - b) <= epsilon;
}

pub fn epsilonNotEql(a: f32, b: f32) bool {
    return @abs(a - b) > epsilon;
}
