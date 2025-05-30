const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const GameApp = @import("yume").GameApp;
const Mat4 = @import("yume").Mat4;

const gizmo = @import("../gizmo.zig");
const Editor = @import("../Editor.zig");
const ComponentEditor = @import("editors.zig").ComponentEditor;

const Self = @This();

allocator: std.mem.Allocator,

pub fn asComponentEditor() ComponentEditor {
    return .{
        .init = Self.init,
        .deinit = Self.deinit,
        .edit = Self.edit,
        .gizmo = Self.onGizmo,
        .flags = .{ .no_disable = true },
    };
}

fn init(a: std.mem.Allocator) *anyopaque {
    const ptr = a.create(Self) catch @panic("OOM");
    ptr.* = Self{ .allocator = a };
    return ptr;
}

fn deinit(ptr: *anyopaque) void {
    const me = @as(*Self, @ptrCast(@alignCast(ptr)));
    me.allocator.destroy(me);
}

fn edit(_: *anyopaque, entity: ecs.Entity, _: ecs.Entity, ctx: *GameApp) void {
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

    {
        if (c.ImGui_BeginCombo("Clear Mode", @tagName(cam.clear_mode), 0)) {
            defer c.ImGui_EndCombo();

            const clear_mode_fields = @typeInfo(ecs.components.Camera.ClearMode).Enum.fields;
            inline for (clear_mode_fields) |field| {
                var selected = @intFromEnum(cam.clear_mode) == field.value;
                if (c.ImGui_SelectableBoolPtr(field.name, &selected, 0)) {
                    cam.clear_mode = @enumFromInt(field.value);
                    cam.clear_value = switch (cam.clear_mode) {
                        .zero => .{ .zero = {} },
                        .color => .{ .color = ecs.components.Camera.default_clear_color },
                    };
                }
            }
        }
    }
    switch (cam.clear_mode) {
        .zero => {},
        .color => {
            _ = c.ImGui_ColorEdit4("Clear Color", &cam.clear_value.color, c.ImGuiColorEditFlags_NoInputs);
        },
    }
}

fn onGizmo(_: *anyopaque, entity: ecs.Entity, _: ecs.Entity, ctx: *GameApp) void {
    var cam = ctx.world.getMut(entity, ecs.components.Camera).?;
    var transform = ctx.world.get(entity, ecs.components.WorldTransform).?;
    switch (cam.opts.kind) {
        .perspective => {
            const decomposed = transform.decompose();
            const aspect = Editor.instance().game_window.game_view_size.x / Editor.instance().game_window.game_view_size.y;
            cam.updateMatrices(decomposed.translation, decomposed.rotation.toEuler(), aspect);
            gizmo.drawFrustum(cam.view_projection.inverse() catch Mat4.IDENTITY) catch {};
        },
        .orthographic => @panic("TODO"),
    }
}
