const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const GameApp = @import("yume").GameApp;
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

pub fn edit(_: *anyopaque, entity: ecs.Entity, _: ecs.Entity, ctx: *GameApp) void {
    var light = ctx.world.getMut(entity, ecs.components.PointLight).?;
    c.ImGui_PushID("point-light-editor");
    var changed: bool = false;
    changed = changed or c.ImGui_ColorEdit3("Color", @ptrCast(&light.color), 0);
    changed = changed or c.ImGui_DragFloatEx("Intensity", @ptrCast(&light.intensity), 0.01, 0, 10, null, 0);
    if (changed) {
        ctx.world.modified(entity, ecs.components.PointLight);
    }
    c.ImGui_PopID();
}

pub fn asComponentEditor() ComponentEditor {
    return .{
        .init = @This().init,
        .deinit = @This().deinit,
        .edit = @This().edit,
    };
}
