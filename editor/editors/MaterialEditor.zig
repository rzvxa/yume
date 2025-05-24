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
    var mat = ctx.world.getMut(entity, ecs.components.Material).?;
    if (c.ImGui_BeginCombo("Shader", "selected shader", c.ImGuiComboFlags_None)) {
        // Resources.findResourceNode
        defer c.ImGui_EndCombo();
        _ = c.ImGui_Selectable("A");
        _ = c.ImGui_Selectable("PBR");
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

pub fn asComponentEditor() ComponentEditor {
    return .{
        .init = @This().init,
        .deinit = @This().deinit,
        .edit = @This().edit,
    };
}
