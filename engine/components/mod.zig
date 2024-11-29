const std = @import("std");

const yume = @import("../root.zig");
const Vec3 = yume.Vec3;
const Mesh = @import("../rendering/Mesh.zig");

pub const Position = struct { inner: Vec3 = Vec3.as(0) };
pub const Rotation = struct { inner: Vec3 = Vec3.as(0) };
pub const Scale = struct { inner: Vec3 = Vec3.as(0) };

pub const MeshComp = struct { inner: ?Mesh = null };

pub const Camera = @import("Camera.zig");
