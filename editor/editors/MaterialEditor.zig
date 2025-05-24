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

pub fn init(a: std.mem.Allocator) *anyopaque {
    const ptr = a.create(@This()) catch @panic("OOM");
    ptr.* = @This(){
        .allocator = a,
        .shaders_root_uri = Resources.Uri.parse(a, "builtin-shaders://") catch @panic("OOM"),
    };
    return ptr;
}

pub fn deinit(ptr: *anyopaque) void {
    const me = @as(*@This(), @ptrCast(@alignCast(ptr)));
    me.shaders_root_uri.deinit(me.allocator);
    me.allocator.destroy(me);
}

pub fn edit(ptr: *anyopaque, entity: ecs.Entity, _: ecs.Entity, ctx: *GameApp) void {
    const me = @as(*@This(), @ptrCast(@alignCast(ptr)));
    var mat = ctx.world.getMut(entity, ecs.components.Material).?;
    if (c.ImGui_BeginCombo("Shader", "selected shader", c.ImGuiComboFlags_None)) {
        defer c.ImGui_EndCombo();
        const shaders = Resources.findResourceNodeByUri(&me.shaders_root_uri) catch @panic("shaders not found") orelse unreachable;
        var dfs = shaders.dfs(me.allocator, .pre) catch @panic("Failed to walk the shaders");
        defer dfs.deinit();
        while (dfs.next() catch @panic("Failed to walk the shaders")) |e| {
            switch (e.event) {
                .enter => |res| {
                    if (res.node != .resource) continue;
                    if (Resources.getResourceType(res.node.resource) catch .unknown != .shader) continue;
                    const path = res.node.path() catch "ERROR";
                    // var buf: [std.fs.max_path_bytes]u8 = undefined;
                    // const pathz = std.fmt.bufPrintZ(&buf, "{s}", .{std.fs.path.basename(path)}) catch "ERROR";
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

pub fn asComponentEditor() ComponentEditor {
    return .{
        .init = @This().init,
        .deinit = @This().deinit,
        .edit = @This().edit,
    };
}
