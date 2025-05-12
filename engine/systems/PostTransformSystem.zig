const c = @import("clibs");

const std = @import("std");

const ecs = @import("../ecs.zig");
const Quat = @import("../math3d.zig").Quat;
const Mat4 = @import("../math3d.zig").Mat4;

const LocalTransform = ecs.components.LocalTransform;
const WorldTransform = ecs.components.WorldTransform;

pub fn registerTo(world: ecs.World, comptime scope: enum { world, local }, transform_sync_sys: ecs.Entity) ecs.Entity {
    return switch (scope) {
        .world => world.systemFn(
            "PostWorldTransform",
            transform_sync_sys,
            systemFor(WorldTransform).exec,
        ),
        .local => world.systemFn(
            "PostLocalTransform",
            transform_sync_sys,
            systemFor(LocalTransform).exec,
        ),
    };
}

fn systemFor(
    comptime T: type,
) type {
    return struct {
        fn exec(transforms: []T) void {
            for (transforms) |*transform| {
                transform.dirty = false;
            }
        }
    };
}
