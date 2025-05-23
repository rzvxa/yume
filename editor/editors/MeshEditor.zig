const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const assets = @import("yume").assets;
const Assets = assets.Assets;
const GameApp = @import("yume").GameApp;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;
const Quat = @import("yume").Quat;

const Project = @import("../Project.zig");
const ProjectExplorerWindow = @import("../windows/ProjectExplorerWindow.zig");
const ComponentEditor = @import("editors.zig").ComponentEditor;

const Self = @This();

allocator: std.mem.Allocator,
new_handle: ?assets.AssetHandle = null,

pub fn init(a: std.mem.Allocator) *anyopaque {
    const ptr = a.create(@This()) catch @panic("OOM");
    ptr.* = @This(){ .allocator = a };
    return ptr;
}

pub fn deinit(ptr: *anyopaque) void {
    const me = @as(*@This(), @ptrCast(@alignCast(ptr)));
    me.allocator.destroy(me);
}

pub fn edit(ptr: *anyopaque, entity: ecs.Entity, _: ecs.Entity, ctx: *GameApp) void {
    const me = @as(*@This(), @ptrCast(@alignCast(ptr)));
    var mesh = ctx.world.getMut(entity, ecs.components.Mesh).?;
    if (me.new_handle) |new_handle| {
        new_handle_op: {
            const new_mesh = Assets.get(new_handle.unbox(.mesh)) catch break :new_handle_op;
            Assets.release(mesh.handle) catch {
                Assets.release(new_mesh) catch {};
                break :new_handle_op;
            };
            mesh.* = new_mesh.*;
        }
    }
    me.editAssetHandle("Mesh", mesh.handle.toAssetHandle()) catch |err| {
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

fn editAssetHandle(self: *Self, label: [:0]const u8, handle: assets.AssetHandle) !void {
    var urn = handle.uuid.urnZ();
    c.ImGui_PushID(label);
    defer c.ImGui_PopID();
    _ = c.ImGui_InputText("##mesh-reference", &urn, 37, c.ImGuiInputTextFlags_ReadOnly);
    c.ImGui_SameLine();
    if (c.ImGui_Button("...")) {
        try Project.browseAssets(handle, .{
            .locked_filters = &.{
                ProjectExplorerWindow.filterByResourceType(.obj),
            },
            .callback = Project.OnSelectAsset.callback(Self, self, Self.onSelectAsset),
        });
    }
    c.ImGui_SameLine();
    _ = c.ImGui_Text("Mesh");
}

fn onSelectAsset(self: *Self, handle: ?assets.AssetHandle) void {
    self.new_handle = handle;
}
