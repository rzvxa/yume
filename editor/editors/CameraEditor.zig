const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const GameApp = @import("yume").GameApp;

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

pub fn edit(_: *anyopaque, entity: ecs.Entity, _: ecs.Entity, ctx: *GameApp) void {
    var cam = ctx.world.getMut(entity, ecs.components.Camera).?;
    if (c.ImGui_BeginCombo("Camera Type", cam.opts.typeName().ptr, 0)) {
        if (c.ImGui_Selectable(ecs.components.camera.CameraKind.perspective_name)) {
            cam.opts = .{ .kind = .perspective, .data = .{ .perspective = .{} } };
        }
        if (c.ImGui_Selectable(ecs.components.camera.CameraKind.orthographic_name)) {
            cam.opts = .{ .kind = .orthographic, .data = .{ .orthographic = .{} } };
        }
        c.ImGui_EndCombo();
    }

    switch (cam.opts.kind) {
        .perspective => {
            var fov = std.math.radiansToDegrees(cam.opts.data.perspective.fovy_rad);
            _ = c.ImGui_DragFloat("Fov", &fov);
            cam.opts.data.perspective.fovy_rad = std.math.degreesToRadians(fov);
            _ = c.ImGui_DragFloat("Near", &cam.opts.data.perspective.near);
            _ = c.ImGui_DragFloat("Far", &cam.opts.data.perspective.far);
        },
        .orthographic => {
            _ = c.ImGui_DragFloat("Left", &cam.opts.data.orthographic.left);
            _ = c.ImGui_DragFloat("Right", &cam.opts.data.orthographic.right);
            _ = c.ImGui_DragFloat("Bottom", &cam.opts.data.orthographic.bottom);
            _ = c.ImGui_DragFloat("Top", &cam.opts.data.orthographic.top);
            _ = c.ImGui_DragFloat("Near", &cam.opts.data.orthographic.near);
            _ = c.ImGui_DragFloat("Far", &cam.opts.data.orthographic.far);
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
