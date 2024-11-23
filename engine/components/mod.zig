const std = @import("std");

const yume = @import("../root.zig");
const Vec3 = yume.Vec3;

pub const Position = struct { inner: Vec3 = Vec3.as(0) };
pub const Rotation = struct { inner: Vec3 = Vec3.as(0) };
pub const Scale = struct { inner: Vec3 = Vec3.as(0) };

pub const Camera = @import("Camera.zig");
