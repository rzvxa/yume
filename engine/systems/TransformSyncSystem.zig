const c = @import("clibs");

const std = @import("std");

const ecs = @import("../ecs.zig");
const Quat = @import("../math3d.zig").Quat;
const Mat4 = @import("../math3d.zig").Mat4;

const LocalTransform = ecs.components.LocalTransform;
const WorldTransform = ecs.components.WorldTransform;

pub fn registerTo(world: ecs.World) ecs.Entity {
    var entity_desc = c.ecs_entity_desc_t{};
    entity_desc.id = c.ecs_new(world.inner);
    entity_desc.name = "TransformSyncSystem";

    {
        const phase = ecs.systems.PostUpdate;
        const first = ecs.pair(ecs.relations.DependsOn, phase);
        entity_desc.add = &[_]c.ecs_id_t{ first, phase, 0 };
    }

    var system_desc = ecs.SystemDesc{};

    system_desc.query.terms[0] = .{
        .id = ecs.typeId(WorldTransform),
        .inout = ecs.InOut.in_out.cast(),
    };
    system_desc.query.terms[1] = .{
        .id = ecs.typeId(LocalTransform),
        .inout = ecs.InOut.in_out.cast(),
    };
    system_desc.query.terms[2] = .{
        .id = ecs.typeId(WorldTransform),
        .inout = ecs.InOut.in.cast(),
        .src = .{ .id = ecs.query_miscs.Up },
    };

    system_desc.entity = world.createEx(&entity_desc);

    system_desc.callback = @ptrCast(&struct {
        pub fn exec(citer: [*c]c.ecs_iter_t) callconv(.C) void {
            const iter = ecs.Iterator.from(citer);
            const wts = ecs.field(iter, WorldTransform, 0);
            const lts = ecs.field(iter, LocalTransform, 1);
            const parent_wts = ecs.field(iter, WorldTransform, 2);
            system(iter, wts.?, lts.?, parent_wts.?);
        }
    }.exec);
    return world.systemEx(&system_desc);
}

fn system(
    iter: *ecs.Iterator,
    world_transforms: []WorldTransform,
    local_transforms: []LocalTransform,
    parent_world_transforms: []const WorldTransform,
) void {
    _ = iter;
    for (world_transforms, local_transforms, parent_world_transforms) |*wt, *lt, *parent_wt| {
        // no change detected, we can skip
        if (!parent_wt.dirty and !lt.dirty and !wt.dirty) {
            continue;
        }
        wt.dirty = true;
        // prioritize local movements over the world movement, as it's faster to calculate
        if (lt.dirty or parent_wt.dirty) {
            wt.matrix = parent_wt.matrix.mul(lt.matrix);
        } else {
            const parent_inverse = parent_wt.matrix.inverse() catch Mat4.IDENTITY;
            lt.matrix = parent_inverse.mul(wt.matrix);
        }
    }
}
