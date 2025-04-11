const std = @import("std");

const components = @import("../components.zig");
const Quat = @import("../math3d.zig").Quat;
const Mat4 = @import("../math3d.zig").Mat4;

pub fn system(
    positions: []const components.Position,
    rotations: []const components.Rotation,
    scales: []const components.Scale,
    transformMatrices: []components.TransformMatrix,
) void {
    std.debug.print("syscall \n", .{});
    for (positions, rotations, scales, transformMatrices) |p, r, s, *t| {
        std.debug.print("here {?}\n", .{p.value});
        t.value = Mat4.compose(p.value, Quat.fromEuler(r.value), s.value);
    }
}
