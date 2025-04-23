const c = @import("clibs");

const std = @import("std");

const GameApp = @import("yume").GameApp;
const ecs = @import("yume").ecs;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;
const Quat = @import("yume").Quat;

const imutils = @import("../imutils.zig");

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, _: ecs.Entity) Self {
    const self = Self{
        .allocator = allocator,
    };
    return self;
}

pub fn deinit(_: *Self) void {}

pub fn edit(_: *Self, entity: ecs.Entity, ctx: *GameApp) void {
    const transform = ctx.world.getMut(entity, ecs.components.Transform);

    var decomposed = transform.?.value.decompose() catch Mat4.Decomposed.IDENTITY;

    var changed = false;

    if (imutils.collapsingHeaderWithCheckBox("Transform", null, c.ImGuiTreeNodeFlags_DefaultOpen)) {
        if (inputVec3("Position", &decomposed.translation, 0.01)) {
            changed = true;
        }

        var euler = decomposed.rotation.toEuler();
        if (inputVec3("Rotation", &euler, 1)) {
            decomposed.rotation = Quat.fromEuler(euler);
            changed = true;
        }

        if (inputVec3("Scale", &decomposed.scale, 0.01)) {
            changed = true;
        }
    }

    if (changed) {
        transform.?.value = Mat4.recompose(decomposed);
        ctx.world.modified(entity, ecs.components.Transform);
    }
}

pub fn inputVec3(label: [*c]const u8, v: *Vec3, speed: f32) bool {
    c.ImGui_PushID(label);
    defer c.ImGui_PopID();
    var changed = false;
    c.ImGui_PushMultiItemsWidths(3, c.ImGui_CalcItemWidth());
    changed = dragFloatWithSpeed("X", &v.x, speed) or changed;
    c.ImGui_PopItemWidth();
    c.ImGui_SameLineEx(0.0, c.ImGui_GetStyle().*.ItemInnerSpacing.x);
    changed = dragFloatWithSpeed("Y", &v.y, speed) or changed;
    c.ImGui_PopItemWidth();
    c.ImGui_SameLineEx(0.0, c.ImGui_GetStyle().*.ItemInnerSpacing.x);
    changed = dragFloatWithSpeed("Z", &v.z, speed) or changed;
    c.ImGui_PopItemWidth();
    c.ImGui_SameLineEx(0.0, c.ImGui_GetStyle().*.ItemInnerSpacing.x);
    c.ImGui_Text(label);
    return changed;
}

pub fn dragFloatWithSpeed(label: [*c]const u8, v: *f32, speed: f32) bool {
    return c.ImGui_DragFloatEx(label, v, speed, 0, 0, null, 0);
}
