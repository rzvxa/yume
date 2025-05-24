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
transform_mode: enum { local, world } = .local,

pub fn init(allocator: std.mem.Allocator, _: ecs.Entity) Self {
    const self = Self{
        .allocator = allocator,
    };
    return self;
}

pub fn deinit(_: *Self) void {}

pub fn edit(self: *Self, entity: ecs.Entity, ctx: *GameApp) void {
    c.ImGui_SetNextItemAllowOverlap(); // this only works if header doesn't have a checkbox
    const open = imutils.collapsingHeaderWithCheckBox("Transform", null, c.ImGuiTreeNodeFlags_DefaultOpen);
    {
        c.ImGui_SameLine();
        var mode: c_int = switch (self.transform_mode) {
            .local => 0,
            .world => 1,
        };
        const cursor_x = c.ImGui_GetCursorPosX();
        const combo_width = @max(
            c.ImGui_CalcTextSize("Local").x,
            c.ImGui_CalcTextSize("World").x,
        ) + c.ImGui_GetStyle().*.FramePadding.x * 2 + 30;
        c.ImGui_SetNextItemWidth(combo_width);
        c.ImGui_SetCursorPosX(cursor_x + @max(c.ImGui_GetContentRegionAvail().x - combo_width, 0));
        if (c.ImGui_ComboChar("##mode", &mode, &[_][*:0]const u8{ "Local", "World" }, 2)) {
            if (mode == 1) {
                self.transform_mode = .world;
            } else {
                self.transform_mode = .local;
            }
        }
    }
    if (!open) return;

    const transform_matrix = switch (self.transform_mode) {
        .local => &ctx.world.getMut(entity, ecs.components.LocalTransform).?.matrix,
        .world => &ctx.world.getMut(entity, ecs.components.WorldTransform).?.matrix,
    };

    var decomposed = transform_matrix.decompose() catch Mat4.Decomposed.IDENTITY;
    var changed = false;

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

    if (changed) {
        transform_matrix.* = Mat4.recompose(decomposed);
        switch (self.transform_mode) {
            .local => ctx.world.modified(entity, ecs.components.LocalTransform),
            .world => ctx.world.modified(entity, ecs.components.WorldTransform),
        }
    }
}

fn inputVec3(label: [*c]const u8, v: *Vec3, speed: f32) bool {
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

fn dragFloatWithSpeed(label: [*c]const u8, v: *f32, speed: f32) bool {
    return c.ImGui_DragFloatEx(label, v, speed, 0, 0, null, 0);
}
