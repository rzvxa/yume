const math = @import("../math/mod.zig");
const Mat4 = math.Mat4;
const Mat3 = math.Mat3;
const Vec3 = math.Vec3;

pub fn mat4(translation: *const Vec3, rotation: *const Vec3, scale: *const Vec3) Mat4 {
    const c3 = @cos(rotation.z);
    const s3 = @sin(rotation.z);
    const c2 = @cos(rotation.x);
    const s2 = @sin(rotation.x);
    const c1 = @cos(rotation.y);
    const s1 = @sin(rotation.y);
    return Mat4.new(
        scale.x * (c1 * c3 + s1 * s2 * s3),
        scale.x * (c2 * s3),
        scale.x * (c1 * s2 * s3 - c3 * s1),
        0,

        scale.y * (c3 * s1 * s2 - c1 * s3),
        scale.y * (c2 * c3),
        scale.y * (c1 * c3 * s2 + s1 * s3),
        0,

        scale.z * (c2 * s1),
        scale.z * (-s2),
        scale.z * (c1 * c2),
        0,

        translation.x,
        translation.y,
        translation.z,
        1,
    );
}

pub fn normalMatrix(rotation: *const Vec3, scale: *const Vec3) Mat3 {
    const c3 = @cos(rotation.z);
    const s3 = @sin(rotation.z);
    const c2 = @cos(rotation.x);
    const s2 = @sin(rotation.x);
    const c1 = @cos(rotation.y);
    const s1 = @sin(rotation.y);
    const inv_scale: Vec3 = Vec3.as(1).sub(scale.*);

    return Mat3.new(
        inv_scale.x * (c1 * c3 + s1 * s2 * s3),
        inv_scale.x * (c2 * s3),
        inv_scale.x * (c1 * s2 * s3 - c3 * s1),

        inv_scale.y * (c3 * s1 * s2 - c1 * s3),
        inv_scale.y * (c2 * c3),
        inv_scale.y * (c1 * c3 * s2 + s1 * s3),

        inv_scale.z * (c2 * s1),
        inv_scale.z * (-s2),
        inv_scale.z * (c1 * c2),
    );
}
