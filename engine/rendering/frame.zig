const yume = @import("../root.zig");

const Vec4 = yume.Vec4;
const Mat4 = yume.Mat4;

pub const GlobalUbo = struct {
    projection: Mat4 = Mat4.new(1),
    view: Mat4 = Mat4.fromValue(1),
    ambient_light_color: Vec4 = Vec4.new(1, 1, 1, 0.02),
};
