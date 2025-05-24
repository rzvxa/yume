const c = @import("clibs");
const std = @import("std");
const log = std.log.scoped(.material);

const ecs = @import("../ecs.zig");
const GameApp = @import("../GameApp.zig");
const assets = @import("../assets.zig");
const Assets = assets.Assets;
const Dynamic = @import("../serialization/dynamic.zig").Dynamic;

const Uuid = @import("../uuid.zig").Uuid;

pub const Material = extern struct {
    handle: assets.MaterialHandle,
    pipeline: c.VkPipeline,
    pipeline_layout: c.VkPipelineLayout,

    rsc_count: u8,
    rsc_handles: [*c]assets.AssetHandle,
    rsc_descriptor_set: c.VkDescriptorSet,

    pub fn editorIcon() [*:0]const u8 {
        return "editor://icons/material.png";
    }

    pub fn deinit(self: *Material) void {
        Assets.release(self.handle) catch {};
    }

    pub fn default(ptr: *Material, _: ecs.Entity, _: *GameApp, rr: ecs.ResourceResolver) callconv(.C) bool {
        const handle = rr("builtin://materials/default.mat").toAssetHandle() catch |err| {
            log.err("encountered error on creating the default material, {}", .{err});
            return false;
        };
        ptr.* = (Assets.get(handle.unbox(.material)) catch return false).*;
        return true;
    }

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        return .{ .type = .string, .value = .{ .string = try allocator.dupeZ(u8, &self.handle.uuid.urn()) } };
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, _: std.mem.Allocator) !void {
        const urn = try value.expectString();
        const uuid = try Uuid.fromUrnSlice(std.mem.span(urn));
        self.* = (try Assets.get(assets.MaterialHandle{ .uuid = uuid })).*;
    }
};
