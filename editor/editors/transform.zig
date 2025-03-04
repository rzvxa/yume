const c = @import("clibs");

const std = @import("std");

const Object = @import("yume").Object;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;
const Quat = @import("yume").Quat;

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, _: *Object) Self {
    const self = Self{
        .allocator = allocator,
    };
    return self;
}

pub fn deinit(_: *Self) void {}

pub fn edit(_: *Self, obj: *Object) void {
    const components = obj.transform.decompose();

    var pos = components.translation;
    var rot = components.rotation.toEuler();
    var scale = components.scale;

    var changed = false;

    if (inputVec3("Position", &pos, 0.01)) {
        changed = true;
    }
    // std.log.debug("rot: {} {}", .{ rot, components.rotation });

    if (inputVec3("Rotation", &rot, 1)) {
        changed = true;
    }

    if (inputVec3("Scale", &scale, 0.01)) {
        changed = true;
    }
    obj.transform = Mat4.compose(pos, Quat.fromEuler(rot), scale);
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
