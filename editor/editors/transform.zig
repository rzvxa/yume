const c = @import("clibs");

const std = @import("std");

const GameApp = @import("yume").GameApp;
const ecs = @import("yume").ecs;
const components = @import("yume").components;
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
    const position = ctx.world.getMut(entity, components.Position);
    const rotation = ctx.world.getMut(entity, components.Rotation);
    const scale = ctx.world.getMut(entity, components.Scale);

    var changed = false;

    if (imutils.collapsingHeaderWithCheckBox("Transform", null, c.ImGuiTreeNodeFlags_DefaultOpen)) {
        if (position) |pos| {
            if (inputVec3("Position", &pos.value, 0.01)) {
                changed = true;
            }
        }

        if (rotation) |rot| {
            if (inputVec3("Rotation", &rot.value, 1)) {
                changed = true;
            }
        }

        if (scale) |skale| {
            if (inputVec3("Scale", &skale.value, 0.01)) {
                changed = true;
            }
        }
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
