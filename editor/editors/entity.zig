const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const GameApp = @import("yume").GameApp;
const utils = @import("yume").utils;
const imutils = @import("../imutils.zig");

const Editor = @import("../Editor.zig");

const Self = @This();

allocator: std.mem.Allocator,

name_str: imutils.ImString,

pub fn init(allocator: std.mem.Allocator, entity: ecs.Entity, ctx: *GameApp) Self {
    const name = ctx.world.getName(entity);
    return .{
        .allocator = allocator,
        .name_str = imutils.ImString.fromSlice(allocator, name) catch @panic("OOM"),
    };
}

pub fn deinit(self: *Self) void {
    self.name_str.deinit();
}

pub fn edit(self: *Self, entity: ecs.Entity, ctx: *GameApp) void {
    const metaName = ctx.world.getMetaName(entity);
    const pathName = ctx.world.getPathName(entity);
    var has_path_name = pathName != null;

    self.name_str.set(pathName orelse metaName) catch @panic("OOM");

    const icon = Editor.object_icon_ds;
    const avail = c.ImGui_GetContentRegionAvail();
    const old_pad_y = c.ImGui_GetStyle().*.FramePadding.y;
    c.ImGui_GetStyle().*.FramePadding.y = 0;
    _ = c.ImGui_BeginChildFrameEx(c.ImGui_GetID("entity type icon"), c.ImVec2{ .x = 48, .y = 48 }, c.ImGuiWindowFlags_NoBackground);
    c.ImGui_Image(icon, c.ImVec2{ .x = 48, .y = 48 });
    c.ImGui_EndChildFrame();
    c.ImGui_GetStyle().*.FramePadding.y = old_pad_y;

    c.ImGui_SameLine();

    _ = c.ImGui_BeginChildFrameEx(c.ImGui_GetID("meta"), c.ImVec2{ .x = avail.x - 48, .y = 48 }, c.ImGuiWindowFlags_NoBackground);
    c.ImGui_TextDisabled("Entity(#%d):", entity);
    c.ImGui_Separator();

    var enabled = true;
    _ = c.ImGui_Checkbox("###enabled", &enabled);
    c.ImGui_SameLine();

    const renamed = imutils.DelayedInputTextEx(
        "###Name",
        self.name_str.buf,
        self.name_str.size(),
        c.ImGuiInputTextFlags_CallbackResize,
        imutils.ImString.InputTextCallback,
        &self.name_str,
    );

    const name = self.name_str.span();
    if (renamed) {
        if (has_path_name) {
            _ = Editor.trySetUniquePathName(
                ctx.world,
                entity,
                name,
                self.allocator,
            ) catch |err| switch (err) {
                error.Cancel => {},
                else => @panic("Failed to set path name as unqiue"),
            };
        } else {
            _ = ctx.world.setMetaName(entity, name);
        }
    }

    c.ImGui_EndChildFrame();

    const identifiers_flags = if (has_path_name) c.ImGuiTreeNodeFlags_DefaultOpen else 0;

    if (c.ImGui_TreeNodeEx("Identifiers", identifiers_flags)) {
        if (c.ImGui_Checkbox("Use name as unique identifier", &has_path_name)) {
            if (has_path_name) {
                _ = Editor.trySetUniquePathName(
                    ctx.world,
                    entity,
                    name,
                    self.allocator,
                ) catch |err| switch (err) {
                    error.Cancel => {},
                    else => @panic("Failed to set path name as unqiue"),
                };
            } else {
                _ = ctx.world.setPathName(entity, null);
                _ = ctx.world.setMetaName(entity, name);
            }
        }
        c.ImGui_SameLine();
        imutils.helpMessage(
            \\Unique identifiers can be used to lookup entities with human readable names, When this option is disabled entity is identifiable only through its entity ID.
            \\
            \\These identifiers as the name suggests have to be unique in the scope of their parents.
            \\This is because the identifier value is directly used for lookups in a hashmap.
            \\
            \\Editor handles uniqueness of identifiers similar to a file manager - by suggesting renames with suffixes on pasting/creation,
            \\However when interacting with the entities programmatically a violation of this rule can cause runtime panics as of now.
        );

        {
            c.ImGui_BeginDisabled(true);
            _ = c.ImGui_InputText("Symbol", @constCast("TODO"), 5, 0);
            _ = c.ImGui_InputText("Alias", @constCast("TODO"), 5, 0);
            c.ImGui_EndDisabled();
        }

        c.ImGui_TreePop();
    }
}
