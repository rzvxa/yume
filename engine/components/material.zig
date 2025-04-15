const c = @import("clibs");
const std = @import("std");

const ecs = @import("../ecs.zig");
const GameApp = @import("../GameApp.zig");

const Uuid = @import("../uuid.zig").Uuid;

pub const Material = extern struct {
    uuid: Uuid,
    texture_set: c.VkDescriptorSet = null,
    pipeline: c.VkPipeline,
    pipeline_layout: c.VkPipelineLayout,

    pub fn default(ptr: *align(8) Material, _: ecs.Entity, _: *GameApp) callconv(.C) bool {
        ptr.* = .{
            .uuid = Uuid.new(),
            .pipeline = null,
            .pipeline_layout = null,
        };
        return true;
    }
};
