const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const GameApp = @import("yume").GameApp;
const assets = @import("yume").assets;
const Assets = assets.Assets;
const Shader = @import("yume").shading.Shader;
const Material = @import("yume").shading.Material;
const Uuid = @import("yume").Uuid;
const Vec4 = @import("yume").Vec4;
const Mat4 = @import("yume").Mat4;
const Quat = @import("yume").Quat;

const Editor = @import("../Editor.zig");
const ComponentEditor = @import("editors.zig").ComponentEditor;
const imutils = @import("../imutils.zig");

const Resources = @import("../Resources.zig");

const Self = @This();

allocator: std.mem.Allocator,
shaders_root_uri: Resources.Uri,

pub fn asComponentEditor() ComponentEditor {
    return .{
        .init = @This().init,
        .deinit = @This().deinit,
        .edit = @This().editAsComponent,
    };
}

fn init(a: std.mem.Allocator) *anyopaque {
    const ptr = a.create(@This()) catch @panic("OOM");
    ptr.* = @This(){
        .allocator = a,
        .shaders_root_uri = Resources.Uri.parse(a, "builtin-shaders://") catch @panic("OOM"),
    };
    return ptr;
}

fn deinit(ptr: *anyopaque) void {
    const me = @as(*@This(), @ptrCast(@alignCast(ptr)));
    me.shaders_root_uri.deinit(me.allocator);
    me.allocator.destroy(me);
}

fn editAsComponent(ptr: *anyopaque, entity: ecs.Entity, _: ecs.Entity, ctx: *GameApp) void {
    const me = @as(*@This(), @ptrCast(@alignCast(ptr)));
    const mat = ctx.world.getMut(entity, ecs.components.Material).?;
    me.edit(mat, ctx) catch |err| {
        std.log.err("{}", .{err});
        @panic("Failed to edit the material");
    };
}

fn edit(self: *Self, mat: *ecs.components.Material, _: *GameApp) !void {
    _ = imutils.assetHandleInput("Material", mat.ref.handle.toAssetHandle()) catch |err| blk: {
        std.log.err("Failed to display asset handle editor on the Material component, {}", .{err});
        break :blk null;
    };
    const shaders = try Resources.findResourceNodeByUri(&self.shaders_root_uri) orelse unreachable;
    const active_shader = try Resources.getShaderDef(mat.ref.shader.uuid);
    if (c.ImGui_BeginCombo("Shader", active_shader.name, c.ImGuiComboFlags_None)) {
        defer c.ImGui_EndCombo();
        var dfs = try shaders.dfs(self.allocator, .pre);
        defer dfs.deinit();
        while (try dfs.next()) |e| {
            switch (e.event) {
                .enter => |res| {
                    if (res.node != .resource) continue;
                    if (try Resources.getResourceType(res.node.resource) != .shader) continue;
                    const shader = try Resources.getShaderDef(res.node.resource);
                    _ = c.ImGui_Selectable(shader.name);
                },
                .leave => {},
            }
        }
    }

    const material_def = try Resources.getMaterialDefMut(mat.ref.handle.uuid);
    var max_label_width: f32 = 0;
    for (active_shader.layout) |uniform| {
        max_label_width = @max(max_label_width, c.ImGui_CalcTextSize(uniform.name).x + c.ImGui_GetStyle().*.FramePadding.x * 2);
    }

    var updated: bool = false;
    for (active_shader.layout, material_def.resources, mat.ref.rsc_handles[0..mat.ref.rsc_count]) |uniform, *res_def, res_handle| {
        c.ImGui_PushIDPtr(res_def);
        defer c.ImGui_PopID();

        const text_height = c.ImGui_GetTextLineHeightWithSpacing();

        c.ImGui_Text(uniform.name);
        c.ImGui_SameLineEx(max_label_width, 0);

        c.ImGui_SetNextItemWidth(text_height * 2 + c.ImGui_GetStyle().*.FramePadding.x * 2);
        if (c.ImGui_BeginCombo("##type", null, c.ImGuiComboFlags_CustomPreview)) {
            defer c.ImGui_EndCombo();

            inline for (@typeInfo(Material.Def.ResourceDef).Union.fields, 0..) |field, i| {
                const tag: std.meta.Tag(Material.Def.ResourceDef) = @enumFromInt(i);
                const icon = resourceBindIcon(tag);
                const display_name = switch (tag) {
                    .uuid => "Texture",
                    .color => "Color",
                    .number => "Number",
                };
                if (c.ImGui_Selectable("##" ++ field.name)) {
                    res_def.* = switch (tag) {
                        .uuid => .{ .uuid = try Resources.getResourceId("builtin://1x1b.png") },
                        .color => .{ .color = [_]u8{255} ** 4 },
                        .number => .{ .number = 1 },
                    };
                    updated = true;
                }
                c.ImGui_SameLineEx(0, 0);
                c.ImGui_Image(try Editor.getImGuiTexture(icon), .{ .x = text_height, .y = text_height });
                c.ImGui_SameLine();
                c.ImGui_Text(display_name);
            }
        }
        if (c.ImGui_BeginComboPreview()) {
            defer c.ImGui_EndComboPreview();
            const icon_uri = resourceBindIcon(std.meta.activeTag(res_def.*));

            c.ImGui_Image(try Editor.getImGuiTexture(icon_uri), .{ .x = text_height, .y = text_height });
        }

        c.ImGui_SameLine();

        const avail = c.ImGui_GetContentRegionAvail();
        switch (res_def.*) {
            .uuid => {
                c.ImGui_SetNextItemWidth(avail.x - c.ImGui_GetStyle().*.FramePadding.x * 2);
                const new_handle = imutils.assetHandleInput("##uuid", res_handle) catch |err| blk: {
                    std.log.err("Failed to display asset handle editor on the Material component, {}", .{err});
                    break :blk null;
                };
                if (new_handle) |h| {
                    res_def.uuid = h.uuid;
                    updated = true;
                }
            },
            .number => {
                const n: *f32 = &res_def.number;
                if (c.ImGui_SliderFloat("##number", @ptrCast(n), 0, 1)) {
                    updated = true;
                }
            },
            .color => |col01| {
                var col = [4]f32{
                    @as(f32, @floatFromInt(col01[0])) / 255,
                    @as(f32, @floatFromInt(col01[1])) / 255,
                    @as(f32, @floatFromInt(col01[2])) / 255,
                    @as(f32, @floatFromInt(col01[3])) / 255,
                };

                if (c.ImGui_ColorEdit4("##color", &col, c.ImGuiColorEditFlags_NoInputs)) {
                    res_def.color = .{
                        @intFromFloat(col[0] * 255),
                        @intFromFloat(col[1] * 255),
                        @intFromFloat(col[2] * 255),
                        @intFromFloat(col[3] * 255),
                    };
                    updated = true;
                }
            },
        }
    }

    if (updated) {
        try Assets.reload(mat.ref.handle, .{});
    }
}

fn resourceBindIcon(tag: std.meta.Tag(Material.Def.ResourceDef)) []const u8 {
    return switch (tag) {
        .uuid => "editor://icons/image-small.png",
        .color => "editor://icons/color-picker-small.png",
        .number => "editor://icons/numpad-small.png",
    };
}
