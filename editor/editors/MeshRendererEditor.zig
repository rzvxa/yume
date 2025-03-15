const c = @import("clibs");

const std = @import("std");

const Object = @import("yume").Object;
const Component = @import("yume").Component;
const MeshRenderer = @import("yume").MeshRenderer;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;
const Quat = @import("yume").Quat;

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

pub fn edit(_: *anyopaque, _: *Object, comp: *Component) void {
    const mr = @as(*MeshRenderer, @ptrCast(@alignCast(comp.ptr)));
    var urn = mr.mesh.uuid.urnZ();
    c.ImGui_PushID("mesh-reference");
    _ = c.ImGui_InputText("##mesh-reference", &urn, 37, c.ImGuiInputTextFlags_ReadOnly);
    c.ImGui_SameLine();
    _ = c.ImGui_Button("...");
    c.ImGui_SameLine();
    _ = c.ImGui_Text("Mesh");
    c.ImGui_PopID();

    c.ImGui_PushID("material-reference");
    var material_urn = mr.material.uuid.urnZ();
    _ = c.ImGui_InputText("##material-reference", &material_urn, 37, c.ImGuiInputTextFlags_ReadOnly);
    c.ImGui_SameLine();
    _ = c.ImGui_Button("...");
    c.ImGui_SameLine();
    _ = c.ImGui_Text("Material");
    c.ImGui_PopID();
}

pub fn asComponentEditor() ComponentEditor {
    return .{
        .init = @This().init,
        .deinit = @This().deinit,
        .edit = @This().edit,
    };
}
