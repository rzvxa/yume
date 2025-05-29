const c = @import("clibs");
const std = @import("std");

const assets = @import("assets.zig");
const Assets = @import("assets.zig").Assets;
const Engine = @import("VulkanEngine.zig");
const Uuid = @import("uuid.zig").Uuid;
const Vec4 = @import("math3d.zig").Vec4;

const log = std.log.scoped(.shading);

pub const Shader = struct {
    pub const Def = struct {
        pub const Passes = struct {
            vertex: Uuid,
            fragment: Uuid,
        };

        pub const Uniform = struct {
            pub const BindingKind = enum {
                texture,
                cube,
            };

            name: [:0]const u8,
            kind: BindingKind,

            pub fn deinit(uni: *Uniform, allocator: std.mem.Allocator) void {
                allocator.free(uni.name);
            }

            pub fn bindingLayoutHash(layout: []const Uniform) u32 {
                var hash: u32 = 0;
                const prime: u32 = 31;

                for (layout) |uniform| {
                    hash = hash * prime + @intFromEnum(uniform.kind);
                }

                return hash;
            }
        };

        name: [:0]const u8,
        passes: Passes,
        layout: []Uniform,

        pub fn deinit(def: *Def, allocator: std.mem.Allocator) void {
            allocator.free(def.name);
            for (0..def.layout.len) |i| {
                def.layout[i].deinit(allocator);
            }
            allocator.free(def.layout);
        }
    };

    pub const Modules = struct {
        vertex: Engine.ShaderModule,
        fragment: Engine.ShaderModule,
    };

    handle: assets.ShaderHandle,
    modules: Modules,
};

pub const Material = struct {
    pub const Def = struct {
        pub const ResourceDef = union(enum) {
            uuid: Uuid,
            number: f32,
            color: [4]u8,

            pub fn get(rd: ResourceDef, comptime kind: Shader.Def.Uniform.BindingKind) !switch (kind) {
                .texture => *assets.TextureHandle.BackingType,
                .cube => @compileError("TODO"),
            } {
                switch (kind) {
                    .texture => switch (rd) {
                        .uuid => |uuid| {
                            const texture_handle = (assets.ImageHandle{ .uuid = uuid }).toTexture();
                            const tex = try Assets.get(texture_handle);
                            return tex;
                        },
                        .color => |color| return try Assets.getColorTexture(color),
                        .number => |n| return try Assets.getColorTexture([_]u8{@intFromFloat(n * 255)} ** 4),
                    },
                    .cube => unreachable,
                }
            }

            pub fn jsonParse(a: std.mem.Allocator, jrs: anytype, opts: anytype) !@This() {
                switch (try jrs.peekNextTokenType()) {
                    .string => return .{ .uuid = try std.json.innerParse(Uuid, a, jrs, opts) },
                    .number => {
                        const n = try jrs.next();
                        const number = std.fmt.parseFloat(f32, n.number) catch return error.SyntaxError;
                        return .{ .number = number };
                    },
                    .object_begin => _ = try jrs.next(),
                    else => return error.UnexpectedToken,
                }

                // generic value parsing, it is a object with a single key value where key is the type of the value

                const tk = try jrs.next();

                const field_name = switch (tk) {
                    .string => |slice| slice,
                    else => return error.UnexpectedToken,
                };

                const result = if (std.mem.eql(u8, field_name, "color")) blk: {
                    const color = try std.json.innerParse(Vec4, a, jrs, opts);
                    break :blk .{
                        .color = [4]u8{
                            @intFromFloat(color.x * 255),
                            @intFromFloat(color.y * 255),
                            @intFromFloat(color.z * 255),
                            @intFromFloat(color.w * 255),
                        },
                    };
                } else {
                    return error.UnexpectedToken;
                };

                if (try jrs.next() != .object_end) return error.UnexpectedEndOfInput;

                return result;
            }
        };

        name: [:0]const u8,
        shader: Uuid,
        resources: []ResourceDef,

        pub fn deinit(def: *Def, allocator: std.mem.Allocator) void {
            allocator.free(def.name);
            allocator.free(def.resources);
        }

        pub fn jsonParse(a: std.mem.Allocator, jrs: anytype, opts: anytype) !@This() {
            var tk = try jrs.next();
            if (tk != .object_begin) return error.UnexpectedEndOfInput;

            var result: Def = undefined;
            var resources: ?[]ResourceDef = null;

            while (true) {
                tk = try jrs.nextAlloc(a, .alloc_if_needed);
                if (tk == .object_end) break;

                const field_name = switch (tk) {
                    inline .string, .allocated_string => |slice| slice,
                    else => {
                        log.err("{}\n", .{tk});
                        return error.UnexpectedToken;
                    },
                };

                if (std.mem.eql(u8, field_name, "name")) {
                    result.name = switch (try jrs.next()) {
                        inline .string => |slice| try a.dupeZ(u8, slice),
                        else => {
                            log.err("{}\n", .{tk});
                            return error.UnexpectedToken;
                        },
                    };
                } else if (std.mem.eql(u8, field_name, "shader")) {
                    result.shader = try std.json.innerParse(Uuid, a, jrs, opts);
                } else if (std.mem.eql(u8, field_name, "resources")) {
                    resources = try std.json.innerParse([]ResourceDef, a, jrs, opts);
                } else {
                    try jrs.skipValue();
                }
            }

            result.resources = resources orelse try a.alloc(ResourceDef, 0);

            return result;
        }
    };

    handle: assets.MaterialHandle,
    shader: assets.ShaderHandle,

    pipeline: Engine.Pipeline,
    pipeline_layout: Engine.PipelineLayout,

    rsc_count: u8,
    rsc_handles: [*c]assets.AssetHandle,
    rsc_descriptor_set: Engine.DescriptorSet,
};
