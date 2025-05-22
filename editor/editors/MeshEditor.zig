const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const assets = @import("yume").assets;
const GameApp = @import("yume").GameApp;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;
const Quat = @import("yume").Quat;

const Project = @import("../Project.zig");
const ProjectExplorerWindow = @import("../windows/ProjectExplorerWindow.zig");
const ComponentEditor = @import("editors.zig").ComponentEditor;

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(a: std.mem.Allocator) *anyopaque {
    const ptr = a.create(@This()) catch @panic("OOM");
    ptr.* = @This(){ .allocator = a };
    return ptr;
}

pub fn deinit(ptr: *anyopaque) void {
    const me = @as(*@This(), @ptrCast(@alignCast(ptr)));
    me.allocator.destroy(me);
}

pub fn edit(_: *anyopaque, entity: ecs.Entity, _: ecs.Entity, ctx: *GameApp) void {
    var mesh = ctx.world.getMut(entity, ecs.components.Mesh).?;
    editAssetHandle("Mesh", mesh.handle.toAssetHandle()) catch |err| {
        std.log.err("Failed to display asset handle editor on the Mesh component, {}", .{err});
    };
}

pub fn asComponentEditor() ComponentEditor {
    return .{
        .init = @This().init,
        .deinit = @This().deinit,
        .edit = @This().edit,
    };
}

fn editAssetHandle(label: [:0]const u8, handle: assets.AssetHandle) !void {
    var urn = handle.uuid.urnZ();
    c.ImGui_PushID(label);
    defer c.ImGui_PopID();
    _ = c.ImGui_InputText("##mesh-reference", &urn, 37, c.ImGuiInputTextFlags_ReadOnly);
    c.ImGui_SameLine();
    if (c.ImGui_Button("...")) {
        const new_handle = try Project.browseAssets(handle, .{ .locked_filters = &.{ProjectExplorerWindow.filterByResourceType(.obj)} });
        std.log.debug("old_handle: {s}, new_handle: {s}", .{
            handle.uuid.urn(),
            if (new_handle) |h| &h.uuid.urn() else "null",
        });
    }
    c.ImGui_SameLine();
    _ = c.ImGui_Text("Mesh");
}
