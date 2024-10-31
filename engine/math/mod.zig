pub const concept = struct {
    pub usingnamespace @import("common/concept.zig");
    pub usingnamespace @import("types/vec/concept.zig");
    pub usingnamespace @import("types/mat/concept.zig");
};

pub const common = @import("common/functions/common.zig");
pub const exponential = @import("common/functions/exponential.zig");
pub const geometric = @import("common/functions/geometric.zig");
pub const trigonometric = @import("common/functions/trigonometric.zig");

pub const vec = @import("types/vec/vec.zig");
pub const mat = @import("types/mat/mat.zig");

pub const Vec2 = vec.Vec2(f32);
pub const Vec3 = vec.Vec3(f32);
pub const Vec4 = vec.Vec4(f32);
pub const Mat4 = mat.Mat4(f32);
