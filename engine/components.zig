const std = @import("std");

pub const ecs = @import("ecs.zig");

pub const Uuid = @import("components/Uuid.zig").Uuid;

pub const Position = @import("components/transform.zig").Position;
pub const Rotation = @import("components/transform.zig").Rotation;
pub const Scale = @import("components/transform.zig").Scale;
pub const TransformMatrix = @import("components/transform.zig").TransformMatrix;

pub const camera = @import("components/camera.zig");
pub const mesh = @import("components/mesh.zig");

pub const Camera = camera.Camera;
pub const Mesh = mesh.Mesh;

pub const ComponentDef = ecs.ComponentDef;
