const c = @import("clibs");
const std = @import("std");

const ecs = @import("../ecs.zig");
const GameApp = @import("../GameApp.zig");
const AssetsDatabase = @import("../assets.zig").AssetsDatabase;

const Uuid = @import("../uuid.zig").Uuid;

pub const Material = extern struct {
    uuid: Uuid,
    texture_set: c.VkDescriptorSet = null,
    pipeline: c.VkPipeline,
    pipeline_layout: c.VkPipelineLayout,

    pub fn default(ptr: *align(8) Material, _: ecs.Entity, _: *GameApp, rr: ecs.ResourceResolver) callconv(.C) bool {
        const mat = rr("builtin://materials/none.mat");
        if (!mat.found) {
            return false;
        }
        ptr.* = (AssetsDatabase.getOrLoadMaterial(mat.uuid) catch return false).*;
        return true;
    }
};
