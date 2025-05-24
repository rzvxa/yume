const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const GameApp = @import("yume").GameApp;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;
const Quat = @import("yume").Quat;

const ComponentEditor = @import("editors.zig").ComponentEditor;

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
    me.edit(mat, ctx) catch @panic("Failed to edit the material");
}

fn edit(self: *Self, mat: *ecs.components.Material, _: *GameApp) !void {
    if (c.ImGui_BeginCombo("Shader", "selected shader", c.ImGuiComboFlags_None)) {
        defer c.ImGui_EndCombo();
        const shaders = try Resources.findResourceNodeByUri(&self.shaders_root_uri) orelse unreachable;
        var dfs = try shaders.dfs(self.allocator, .pre);
        defer dfs.deinit();
        while (try dfs.next()) |e| {
            switch (e.event) {
                .enter => |res| {
                    if (res.node != .resource) continue;
                    if (try Resources.getResourceType(res.node.resource) != .shader) continue;
                    const path = try res.node.path();
                    _ = c.ImGui_Selectable(path);
                },
                .leave => {},
            }
        }
    }
    c.ImGui_PushID("material-reference");
    defer c.ImGui_PopID();
    var urn = mat.handle.uuid.urnZ();
    _ = c.ImGui_InputText("##material-reference", &urn, 37, c.ImGuiInputTextFlags_ReadOnly);
    c.ImGui_SameLine();
    _ = c.ImGui_Button("...");
    c.ImGui_SameLine();
    _ = c.ImGui_Text("Material");
}
