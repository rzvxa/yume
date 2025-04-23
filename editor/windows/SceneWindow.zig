const c = @import("clibs");

const std = @import("std");

const gizmo = @import("../gizmo.zig");

const ecs = @import("yume").ecs;
const Vec2 = @import("yume").Vec2;
const Vec3 = @import("yume").Vec3;
const Vec4 = @import("yume").Vec4;
const Quat = @import("yume").Quat;
const Mat4 = @import("yume").Mat4;
const Engine = @import("yume").VulkanEngine;
const GameApp = @import("yume").GameApp;
const components = @import("yume").ecs.components;
const AllocatedBuffer = @import("yume").AllocatedBuffer;

const MouseButton = @import("yume").inputs.MouseButton;
const ScanCode = @import("yume").inputs.ScanCode;

const Editor = @import("../Editor.zig");

const FrameData = struct { app: *GameApp, cmd: GameApp.RenderCommand, d: *Self };

const default_cam_distance = 10;
const default_cam_angle = Vec2.make(std.math.degreesToRadians(30), std.math.degreesToRadians(90));

const Self = @This();

camera: components.Camera = components.Camera.makePerspectiveCamera(.{
    .fovy_rad = std.math.degreesToRadians(70.0),
    .far = 200,
    .near = 0.1,
}),

target_pos: Vec3 = Vec3.ZERO,
distance: f32 = default_cam_distance,

active_tool: gizmo.ManipulationTool = .move,

is_perspective: bool = true,

scene_window_rect: c.ImVec4 = std.mem.zeroInit(c.ImVec4, .{}),
scene_view_size: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),
is_scene_window_focused: bool = false,
is_hovered: bool = false,
is_dragging: bool = false,

editor_camera_and_scene_buffer: AllocatedBuffer = undefined,
editor_camera_and_scene_set: c.VkDescriptorSet = null,

frame_userdata: FrameData = undefined,
render_system: ecs.Entity,

pub fn init(ctx: *GameApp) Self {
    var self = Self{
        .render_system = ctx.world.systemEx(&.{
            .entity = ctx.world.create("Editor Render System"),
            .query = std.mem.zeroInit(c.ecs_query_desc_t, .{ .terms = .{
                .{ .id = ecs.typeId(components.Transform) },
                .{ .id = ecs.typeId(components.Mesh) },
                .{ .id = ecs.typeId(components.Material) },
            } }),
            .callback = @ptrCast(&ecs.SystemImpl(sys).exec),
        }),
    };
    self.focus(Vec3.ZERO, default_cam_distance);
    return self;
}

pub fn draw(self: *Self, cmd: Engine.RenderCommand, ctx: *GameApp) !void {
    self.frame_userdata = FrameData{ .app = ctx, .cmd = cmd, .d = self };
    if (c.ImGui_Begin("Scene", null, c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoNav)) {
        self.is_scene_window_focused = c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_None);
        self.is_hovered = c.ImGui_IsWindowHovered(c.ImGuiFocusedFlags_None);
        const editor_image = c.ImGui_GetWindowDrawList();
        self.scene_view_size = c.ImGui_GetWindowSize();

        if (self.is_scene_window_focused and !self.is_dragging) {
            if (c.ImGui_IsKeyPressed(c.ImGuiKey_Q)) {
                self.active_tool = .move;
            } else if (c.ImGui_IsKeyPressed(c.ImGuiKey_W)) {
                self.active_tool = .rotate;
            } else if (c.ImGui_IsKeyPressed(c.ImGuiKey_E)) {
                self.active_tool = .scale;
            } else if (c.ImGui_IsKeyPressed(c.ImGuiKey_R)) {
                self.active_tool = .transform;
            }
        }

        c.ImDrawList_AddCallback(editor_image, extern struct {
            fn f(dl: [*c]const c.ImDrawList, dc: [*c]const c.ImDrawCmd) callconv(.C) void {
                _ = dl;
                const me: *FrameData = @alignCast(@ptrCast(dc.*.UserCallbackData));
                const cr = dc.*.ClipRect;
                me.d.scene_window_rect = cr;
                const w = cr.z - cr.x;
                const h = cr.w - cr.y;

                me.app.engine.beginAdditiveRenderPass(me.cmd);
                c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                    .offset = .{ .x = @intFromFloat(cr.x), .y = @intFromFloat(cr.y) },
                    .extent = .{ .width = @intFromFloat(w), .height = @intFromFloat(h) },
                }});

                const vx = if (cr.x > 0) cr.x else cr.z - me.d.scene_view_size.x;
                c.vkCmdSetViewport(me.cmd, 0, 1, &[_]c.VkViewport{.{
                    .x = vx,
                    .y = cr.y,
                    .width = me.d.scene_view_size.x,
                    .height = me.d.scene_view_size.y,
                    .minDepth = 0.0,
                    .maxDepth = 1.0,
                }});

                const aspect = me.d.scene_view_size.x / me.d.scene_view_size.y;
                me.d.camera.updatePerspectiveProjection(aspect);
                me.d.camera.updateViewProjection();
                _ = c.ecs_run(me.app.world.inner, me.d.render_system, me.app.delta, me);

                c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = GameApp.window_extent,
                }});
            }
        }.f, &self.frame_userdata);
        c.ImDrawList_AddCallback(editor_image, c.ImDrawCallback_ResetRenderState, null);

        const icon_sz = c.ImVec2{ .x = 16, .y = 16 };
        const normal_col = c.ImGui_GetStyle().*.Colors[c.ImGuiCol_Button];
        const active_col = c.ImGui_GetStyle().*.Colors[c.ImGuiCol_ButtonHovered];
        if (c.ImGui_BeginChildFrame(c.ImGui_GetID("##toolbox"), c.ImVec2{
            .x = icon_sz.x + (c.ImGui_GetStyle().*.FramePadding.x * 4),
            .y = (icon_sz.y + c.ImGui_GetStyle().*.FramePadding.y * 4) * 4,
        })) {
            var clicked = false;
            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.active_tool == .move) active_col else normal_col,
            );

            clicked = c.ImGui_ImageButton("##move-tool", Editor.move_tool_icon_ds, icon_sz);
            c.ImGui_PopStyleColor();
            if (clicked) {
                self.active_tool = .move;
            }

            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.active_tool == .rotate) active_col else normal_col,
            );
            clicked = c.ImGui_ImageButton("##rotate-tool", Editor.rotate_tool_icon_ds, icon_sz);
            c.ImGui_PopStyleColor();
            if (clicked) {
                self.active_tool = .rotate;
            }

            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.active_tool == .scale) active_col else normal_col,
            );
            clicked = c.ImGui_ImageButton("##scale-tool", Editor.scale_tool_icon_ds, icon_sz);
            c.ImGui_PopStyleColor();
            if (clicked) {
                self.active_tool = .scale;
            }

            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.active_tool == .transform) active_col else normal_col,
            );
            clicked = c.ImGui_ImageButton("##transform-tool", Editor.transform_tool_icon_ds, icon_sz);
            c.ImGui_PopStyleColor();
            if (clicked) {
                self.active_tool = .transform;
            }

            c.ImGui_EndChildFrame();
        }

        gizmo.newFrame(editor_image, &self.camera.view, self.camera.projection, self.distance, .{
            .x = self.scene_window_rect.x,
            .y = self.scene_window_rect.y,
            .width = self.scene_view_size.x,
            .height = self.scene_view_size.y,
        });

        blk: {
            switch (Editor.instance().selection) {
                .entity => |selection| {
                    const transform = ctx.world.getMut(selection, components.Transform);
                    if (transform == null) {
                        break :blk;
                    }

                    if (c.ImGui_IsKeyPressed(c.ImGuiKey_F)) {
                        self.focus(transform.?.position(), default_cam_distance);
                    }

                    if (ctx.world.get(selection, components.Mesh)) |mesh| {
                        try gizmo.drawBoundingBox(mesh.bounds, transform.?.value);
                    }
                    c.ImGuizmo_PushID_Int(@intCast(selection));
                    if (try gizmo.editTransform(&transform.?.value, self.active_tool)) {
                        ctx.world.modified(selection, components.Transform);
                    }
                    c.ImGuizmo_PopID();
                },
                else => {},
            }
        }
        gizmo.endFrame();
    }
    c.ImGui_End();
}

pub fn update(self: *Self, ctx: *GameApp) !void {
    var input: Vec3 = Vec3.make(0, 0, 0);
    var input_rot: Vec3 = Vec3.make(0, 0, 0);

    const inversed = self.camera.view.inverse() catch Mat4.IDENTITY;
    var decomposed = inversed.decompose() catch Mat4.Decomposed.IDENTITY;
    const basis = decomposed.rotation.toBasisVectors();

    const left = basis.right.mulf(-1);
    const up = basis.up;
    const forward = basis.forward.mulf(-1);

    var in_use: bool = false;

    if (self.is_dragging or self.is_hovered) {
        const wasd = blk: {
            var wasd = Vec3.ZERO;
            // Handle translation inputs (W, A, S, D) relative to view
            wasd = wasd.add(forward.mulf(if (Editor.inputs.isKeyDown(ScanCode.W)) 1 else 0));
            wasd = wasd.sub(forward.mulf(if (Editor.inputs.isKeyDown(ScanCode.S)) 1 else 0));
            wasd = wasd.add(left.mulf(if (Editor.inputs.isKeyDown(ScanCode.A)) 1 else 0));
            wasd = wasd.sub(left.mulf(if (Editor.inputs.isKeyDown(ScanCode.D)) 1 else 0));
            wasd = wasd.add(up.mulf(if (Editor.inputs.isKeyDown(ScanCode.E)) 1 else 0));
            wasd = wasd.sub(up.mulf(if (Editor.inputs.isKeyDown(ScanCode.Q)) 1 else 0));
            wasd = wasd.mulf(5);
            break :blk wasd;
        };
        if (Editor.inputs.isMouseButtonDown(MouseButton.Right)) { // free cam
            in_use = true;
            Editor.inputs.setRelativeMouseMode(true);
            const mouse_delta = Editor.inputs.mouseRelative().mulf(0.5);
            input_rot.y -= mouse_delta.x;
            input_rot.x -= mouse_delta.y;
            input = input.add(wasd);
        } else if (Editor.inputs.isMouseButtonDown(MouseButton.Middle)) {
            if (Editor.inputs.isKeyDown(ScanCode.LeftShift)) { // panning
                in_use = true;
                const mouse_delta = Editor.inputs.mouseDelta();
                input = input.add(left.mulf(mouse_delta.x));
                input = input.add(up.mulf(mouse_delta.y));
            } else { // orbit
                in_use = true;
                const orbit_delta = Editor.inputs.mouseRelative();
                const sensitivity: f32 = 0.005;

                const camera_pos = decomposed.translation;

                self.target_pos = camera_pos.add(forward.mulf(self.distance));

                const offset = camera_pos.sub(self.target_pos);
                const current_distance = offset.len();
                const current_pitch = std.math.asin(offset.y / current_distance);
                const current_yaw = std.math.atan2(offset.x, offset.z);

                const new_pitch = current_pitch + orbit_delta.y * sensitivity;
                const new_yaw = current_yaw - orbit_delta.x * sensitivity;

                const max_pitch = std.math.pi * 0.49;
                var clamped_pitch = new_pitch;
                if (clamped_pitch > max_pitch) {
                    clamped_pitch = max_pitch;
                } else if (clamped_pitch < -max_pitch) {
                    clamped_pitch = -max_pitch;
                }

                const cosPitch = std.math.cos(clamped_pitch);
                const sinPitch = std.math.sin(clamped_pitch);
                const cosYaw = std.math.cos(new_yaw);
                const sinYaw = std.math.sin(new_yaw);
                const new_eye = Vec3.make(
                    self.target_pos.x + current_distance * cosPitch * sinYaw,
                    self.target_pos.y + current_distance * sinPitch,
                    self.target_pos.z + current_distance * cosPitch * cosYaw,
                );

                self.camera.view = Mat4.lookAt(new_eye, self.target_pos, Vec3.UP);
                decomposed = (try self.camera.view.inverse()).decompose() catch Mat4.Decomposed.IDENTITY;
                input = input.add(wasd);
            }
        } else {
            // Mouse wheel for zooming in and out relative to view direction
            const wheel = Editor.inputs.mouseWheel();
            const scroll_speed: f32 = 20;
            if (wheel.y > 0) {
                in_use = true;
                input = input.add(forward.mulf(scroll_speed));
            } else if (wheel.y < 0) {
                in_use = true;
                input = input.sub(forward.mulf(scroll_speed));
            }
        }
    }

    self.is_dragging = in_use;
    if (!in_use) {
        Editor.inputs.setRelativeMouseMode(false);
    }

    // Apply camera movements
    var changed: bool = false;
    if (input.squaredLen() > (0.1 * 0.1)) {
        const camera_delta = input.mulf(ctx.delta);
        decomposed.translation = decomposed.translation.add(camera_delta);
        changed = true;
    }
    if (input_rot.squaredLen() > (0.1 * 0.1)) {
        const rot_delta = input_rot.mulf(ctx.delta);
        const pitch_quat = Quat.fromAxisAngle(Vec3.make(1, 0, 0), rot_delta.x); // Rotate around X (pitch)
        const yaw_quat = Quat.fromAxisAngle(Vec3.make(0, 1, 0), rot_delta.y); // Rotate around Y (yaw)

        decomposed.rotation = yaw_quat.mul(decomposed.rotation).mul(pitch_quat); // Apply rotations
        changed = true;
    }

    if (changed) {
        self.camera.view = try Mat4.recompose(decomposed).inverse();
    }
}

fn focus(self: *Self, target: Vec3, distance: f32) void {
    const eye = target.add(Vec3.make(
        @cos(default_cam_angle.y) * @cos(default_cam_angle.x) * distance,
        @sin(default_cam_angle.x) * distance,
        @sin(default_cam_angle.y) * @cos(default_cam_angle.x) * distance,
    ));
    self.camera.view = Mat4.lookAt(eye, target, Vec3.UP);
    self.distance = distance;
    self.target_pos = target;
}

fn sys(it: *ecs.Iter, matrices: []components.Transform, meshes: []components.Mesh, materials: []components.Material) void {
    const me: *FrameData = @ptrCast(@alignCast(it.param));
    me.app.engine.drawObjects(
        me.cmd,
        matrices,
        meshes,
        materials,
        me.d.editor_camera_and_scene_buffer,
        me.d.editor_camera_and_scene_set,
        &me.d.camera,
    );
}

fn computeOrbitEye(target: Vec3, orbit_angles: Vec2, distance: f32) Vec3 {
    // Spherical coordinate conversion.
    const cosPitch = std.math.cos(orbit_angles.x);
    const sinPitch = std.math.sin(orbit_angles.x);
    const cosYaw = std.math.cos(orbit_angles.y);
    const sinYaw = std.math.sin(orbit_angles.y);

    // Note: Adjust the coordinate computation as needed.
    return Vec3.make(target.x + distance * cosPitch * sinYaw, target.y + distance * sinPitch, target.z + distance * cosPitch * cosYaw);
}
