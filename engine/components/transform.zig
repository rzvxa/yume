const ecs = @import("../ecs.zig");
const Vec3 = @import("../math3d.zig").Vec3;
const Mat4 = @import("../math3d.zig").Mat4;

pub const Position = extern struct { value: Vec3 };
pub const Rotation = extern struct { value: Vec3 };
pub const Scale = extern struct { value: Vec3 };

pub const TransformMatrix = extern struct { value: Mat4 };
