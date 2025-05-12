const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const GameApp = @import("yume").GameApp;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;
const Quat = @import("yume").Quat;

const gizmo = @import("../gizmo.zig");
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
    changed = c.ImGui_ColorEdit3("Color", @ptrCast(&light.color), 0) or changed;

    const fmax = std.math.floatMax(f32);
    const flag = c.ImGuiSliderFlags_ClampZeroRange;
    changed = c.ImGui_DragFloatEx("Intensity", @ptrCast(&light.intensity), 0.01, 0, fmax, null, flag) or changed;
    changed = c.ImGui_DragFloatEx("Range", @ptrCast(&light.range), 0.01, 0, fmax, null, flag) or changed;

    if (changed) {
        ctx.world.modified(entity, ecs.components.PointLight);
    }
    c.ImGui_PopID();
}

fn onGizmo(_: *anyopaque, entity: ecs.Entity, _: ecs.Entity, ctx: *GameApp) void {
    // Get the light’s transform and its world position.
    var transform = ctx.world.get(entity, ecs.components.WorldTransform).?;
    const decomposed = transform.decompose();
    const origin = decomposed.translation;

    const light = ctx.world.get(entity, ecs.components.PointLight).?;

    const radius = light.range;

    const segments: usize = 32;

    const color = c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 228.0 / 255.0, .y = 143.0 / 255.0, .z = 32.0 / 255.0, .w = 1 });

    gizmo.drawSphere(origin, radius, color, segments);
}

pub fn asComponentEditor() ComponentEditor {
    return .{
        .init = @This().init,
        .deinit = @This().deinit,
        .edit = @This().edit,
        .gizmo = @This().onGizmo,
    };
}
