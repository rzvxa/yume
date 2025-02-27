const std = @import("std");

pub const Vec2 = extern struct {
    x: f32,
    y: f32,

    pub const ZERO = make(0.0, 0.0);

    pub inline fn make(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub inline fn scalar(n: f32) Vec2 {
        return .{ .x = n, .y = n };
    }

    pub inline fn toVec3(self: Vec2, z: f32) Vec3 {
        return .{ .x = self.x, .y = self.y, .z = z };
    }
};

pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    const Self = @This();

    pub const ZERO = make(0.0, 0.0, 0.0);

    pub inline fn make(x: f32, y: f32, z: f32) Self {
        return .{ .x = x, .y = y, .z = z };
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
            return Self.ZERO;
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
        return @as(*const [3]f32, @ptrCast(self)).*;
    }
};

pub const Vec4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub const ZERO = make(0.0, 0.0, 0.0, 0.0);

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

    pub inline fn dot(a: Self, b: Self) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    }
};

pub const Quat = extern struct {
    const Self = @This();

    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub const IDENTITY: Self = make(1, 0, 0, 0);

    pub inline fn make(x: f32, y: f32, z: f32, w: f32) Self {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }
};

pub const Mat4 = extern union {
    pub const Mat4Components = struct {
        translation: Vec3,
        rotation: Quat,
        scale: Vec3,
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
            Vec4.make(self.i.x, self.j.x, self.k.x, self.t.x),
            Vec4.make(self.i.y, self.j.y, self.k.y, self.t.y),
            Vec4.make(self.i.z, self.j.z, self.k.z, self.t.z),
            Vec4.make(self.i.w, self.j.w, self.k.w, self.t.w),
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

    pub fn decomposeComponents(self: Self) Mat4Components {
        const t = Vec3.make(
            self.unnamed[3][0],
            self.unnamed[3][1],
            self.unnamed[3][2],
        );

        const sx = Vec3.make(
            self.unnamed[0][0],
            self.unnamed[1][0],
            self.unnamed[2][0],
        ).len();
        const sy = Vec3.make(
            self.unnamed[0][1],
            self.unnamed[1][1],
            self.unnamed[2][1],
        ).len();
        const sz = Vec3.make(
            self.unnamed[0][2],
            self.unnamed[1][2],
            self.unnamed[2][2],
        ).len();
        const s = Vec3.make(sx, sy, sz);
        return .{ .translation = t, .rotation = Quat.IDENTITY, .scale = s };
    }
};

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};
