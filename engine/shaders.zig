const std = @import("std");

const assets = @import("assets.zig");
const Engine = @import("VulkanEngine.zig");
const Uuid = @import("uuid.zig").Uuid;

pub const Shader = struct {
    pub const Def = struct {
        pub const Passes = struct {
            vertex: Uuid,
            fragment: Uuid,
        };

        passes: Passes,
        layouts: []Engine.UniformBindingKind,

        pub fn deinit(def: *Def, allocator: std.mem.Allocator) void {
            allocator.free(def.layouts);
        }
    };

    pub const Modules = struct {
        vertex: Engine.ShaderModule,
        fragment: Engine.ShaderModule,
    };

    handle: assets.ShaderHandle,
    def: Def,
    modules: Modules,
};
