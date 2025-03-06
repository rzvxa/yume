const c = @import("clibs");

const std = @import("std");

const Object = @import("yume").Object;
const Component = @import("yume").Component;
const Camera = @import("yume").Camera;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;
const Quat = @import("yume").Quat;

const ComponentEditor = @import("editors.zig").ComponentEditor;

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(a: std.mem.Allocator) *anyopaque {
    const ptr = a.create(Self) catch @panic("OOM");
    ptr.* = Self{ .allocator = a };
    return ptr;
}

pub fn deinit(ptr: *anyopaque) void {
    const me = @as(*Self, @ptrCast(@alignCast(ptr)));
    me.allocator.destroy(me);
}

pub fn edit(_: *anyopaque, _: *Object, comp: *Component) void {
    const cam = @as(*Camera, @ptrCast(@alignCast(comp.ptr)));
    if (c.ImGui_BeginCombo("Camera Type", cam.opts.typeName().ptr, 0)) {
        if (c.ImGui_Selectable(Camera.CameraKind.perspective_name)) {
            cam.opts = .{ .perspective = .{} };
        }
        if (c.ImGui_Selectable(Camera.CameraKind.orthographic_name)) {
            cam.opts = .{ .orthographic = .{} };
        }
        c.ImGui_EndCombo();
    }

    switch (cam.opts) {
        .perspective => {
            var fov = std.math.radiansToDegrees(cam.opts.perspective.fovy_rad);
            _ = c.ImGui_DragFloat("Fov", &fov);
            cam.opts.perspective.fovy_rad = std.math.degreesToRadians(fov);
            _ = c.ImGui_DragFloat("Near", &cam.opts.perspective.near);
            _ = c.ImGui_DragFloat("Far", &cam.opts.perspective.far);
        },
        .orthographic => {
            _ = c.ImGui_DragFloat("Left", &cam.opts.orthographic.left);
            _ = c.ImGui_DragFloat("Right", &cam.opts.orthographic.right);
            _ = c.ImGui_DragFloat("Bottom", &cam.opts.orthographic.bottom);
            _ = c.ImGui_DragFloat("Top", &cam.opts.orthographic.top);
            _ = c.ImGui_DragFloat("Near", &cam.opts.orthographic.near);
            _ = c.ImGui_DragFloat("Far", &cam.opts.orthographic.far);
        },
    }
}

pub fn asComponentEditor() ComponentEditor {
    return .{
        .init = Self.init,
        .deinit = Self.deinit,
        .edit = Self.edit,
        .flags = .{ .no_disable = true },
    };
}
