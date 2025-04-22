const c = @import("clibs");

const std = @import("std");

const gizmo = @import("../gizmo.zig");

const ecs = @import("yume").ecs;
const Vec2 = @import("yume").Vec2;
const Vec3 = @import("yume").Vec3;
const Vec4 = @import("yume").Vec4;
const Mat4 = @import("yume").Mat4;
const Engine = @import("yume").VulkanEngine;
const GameApp = @import("yume").GameApp;
const components = @import("yume").ecs.components;
const AllocatedBuffer = @import("yume").AllocatedBuffer;

const Editor = @import("../Editor.zig");

const FrameData = struct { app: *GameApp, cmd: GameApp.RenderCommand, d: *Self };

const default_cam_distance = 10;
const default_cam_angle = Vec2.make(std.math.degreesToRadians(45), 0);

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
    self.focus(Vec3.ZERO);
    return self;
}

pub fn draw(self: *Self, cmd: Engine.RenderCommand, ctx: *GameApp) void {
    self.frame_userdata = FrameData{ .app = ctx, .cmd = cmd, .d = self };
    if (c.ImGui_Begin("Scene", null, c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoNav)) {
        self.is_scene_window_focused = c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_None);
        const editor_image = c.ImGui_GetWindowDrawList();
        self.scene_view_size = c.ImGui_GetWindowSize();

        if (self.is_scene_window_focused) {
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

        // FIXME
        blk: {
            switch (Editor.instance().selection) {
                .entity => |selection| {
                    const mesh = ctx.world.getAligned(selection, components.Mesh, 8);
                    if (mesh == null) {
                        break :blk;
                    }

                    const transform = ctx.world.getMut(selection, components.Transform);
                    if (transform == null) {
                        break :blk;
                    }

                    if (c.ImGui_IsKeyPressed(c.ImGuiKey_F)) {
                        self.focus(transform.?.position());
                    }

                    gizmo.drawBoundingBox(mesh.?.bounds, transform.?.value) catch @panic("error");
                    c.ImGuizmo_PushID_Int(@intCast(selection));
                    if (gizmo.editTransform(&transform.?.value, self.active_tool) catch @panic("err")) {
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

fn focus(self: *Self, target: Vec3) void {
    const eye = target.add(Vec3.make(
        @cos(default_cam_angle.y) * @cos(default_cam_angle.x) * default_cam_distance,
        @sin(default_cam_angle.x) * default_cam_distance,
        @sin(default_cam_angle.y) * @cos(default_cam_angle.x) * default_cam_distance,
    ));
    self.camera.view = eye.lookAt(target, Vec3.UP);
    self.distance = default_cam_distance;
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
