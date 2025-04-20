const std = @import("std");

const ecs = @import("../ecs.zig");
const Quat = @import("../math3d.zig").Quat;
const Mat4 = @import("../math3d.zig").Mat4;

pub fn system(
    positions: []const ecs.components.Position,
    rotations: []const ecs.components.Rotation,
    scales: []const ecs.components.Scale,
    transformMatrices: []ecs.components.TransformMatrix,
) void {
    for (positions, rotations, scales, transformMatrices) |p, r, s, *t| {
        t.value = Mat4.compose(p.value, Quat.fromEuler(r.value), s.value);
    }
}
