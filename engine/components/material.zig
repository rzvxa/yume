const c = @import("clibs");
const std = @import("std");

const ecs = @import("../ecs.zig");
const GameApp = @import("../GameApp.zig");
const Assets = @import("../assets.zig").Assets;
const Dynamic = @import("../serialization/dynamic.zig").Dynamic;

const Uuid = @import("../uuid.zig").Uuid;

pub const Material = extern struct {
    uuid: Uuid,
    pipeline: c.VkPipeline,
    pipeline_layout: c.VkPipelineLayout,

    rsc_uuids: [*c]Uuid,
    rsc_descriptor_sets: [*c]c.VkDescriptorSet,
    rsc_count: u8,

    pub fn editorIcon() [*:0]const u8 {
        return "editor://icons/material.png";
    }

    pub fn default(ptr: *Material, _: ecs.Entity, _: *GameApp, rr: ecs.ResourceResolver) callconv(.C) bool {
        const mat = rr("builtin://materials/default.mat");
        if (!mat.found) {
            return false;
        }
        ptr.* = (Assets.getOrLoadMaterial(mat.uuid) catch return false).*;
        return true;
    }

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        return .{ .type = .string, .value = .{ .string = try allocator.dupeZ(u8, &self.uuid.urn()) } };
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, _: std.mem.Allocator) !void {
        const urn = try value.expectString();
        const uuid = try Uuid.fromUrnSlice(std.mem.span(urn));
        self.* = (try Assets.getOrLoadMaterial(uuid)).*;
    }
};
