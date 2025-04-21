const c = @import("clibs");

const std = @import("std");

const gizmo = @import("../gizmo.zig");

const ecs = @import("yume").ecs;
const Vec3 = @import("yume").Vec3;
const Engine = @import("yume").VulkanEngine;
const GameApp = @import("yume").GameApp;
const components = @import("yume").ecs.components;
const AllocatedBuffer = @import("yume").AllocatedBuffer;

const Editor = @import("../Editor.zig");

const ManipulationTool = enum {
    move,
    rotate,
    scale,
};

const FrameData = struct { app: *GameApp, cmd: GameApp.RenderCommand, d: *Self };

const Self = @This();

camera: components.Camera = components.Camera.makePerspectiveCamera(.{
    .fovy_rad = std.math.degreesToRadians(70.0),
    .far = 200,
    .near = 0.1,
}),

camera_pos: Vec3 = Vec3.make(-5.0, 3.0, -10.0),
camera_rot: Vec3 = Vec3.make(0, 0, 0),

active_tool: ManipulationTool = .move,

scene_window_rect: c.ImVec4 = std.mem.zeroInit(c.ImVec4, .{}),
scene_view_size: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),
is_scene_window_focused: bool = false,

editor_camera_and_scene_buffer: AllocatedBuffer = undefined,
editor_camera_and_scene_set: c.VkDescriptorSet = null,

frame_userdata: FrameData = undefined,
render_system: ecs.Entity,

pub fn init(ctx: *GameApp) Self {
    return .{
        .render_system = ctx.world.systemEx(&.{
            .entity = ctx.world.create("Editor Render System"),
            .query = std.mem.zeroInit(c.ecs_query_desc_t, .{ .terms = .{
                .{ .id = ecs.typeId(components.TransformMatrix) },
                .{ .id = ecs.typeId(components.Mesh) },
                .{ .id = ecs.typeId(components.Material) },
            } }),
            .callback = @ptrCast(&ecs.SystemImpl(sys).exec),
        }),
    };
}

pub fn draw(self: *Self, cmd: Engine.RenderCommand, ctx: *GameApp) void {
    self.frame_userdata = FrameData{ .app = ctx, .cmd = cmd, .d = self };
    if (c.ImGui_Begin("Scene", null, c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoNav)) {
        self.is_scene_window_focused = c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_None);
        const editor_image = c.ImGui_GetWindowDrawList();
        self.scene_view_size = c.ImGui_GetWindowSize();

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
                me.d.camera.updateMatrices(me.d.camera_pos, me.d.camera_rot, aspect);
                _ = c.ecs_run(me.app.world.inner, me.d.render_system, me.app.delta, me);
                // me.app.engine.drawObjects(
                //     me.cmd,
                //     me.app.scene.renderables.items,
                //     me.d.editor_camera_and_scene_buffer,
                //     me.d.editor_camera_and_scene_set,
                //     &me.d.camera,
                // );

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
            .y = (icon_sz.y + c.ImGui_GetStyle().*.FramePadding.y * 4) * 3,
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

            c.ImGui_EndChildFrame();
        }

        gizmo.newFrame(editor_image, self.camera.view, self.camera.view_projection, .{
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

                    const transform = ctx.world.get(selection, components.TransformMatrix);
                    if (transform == null) {
                        break :blk;
                    }

                    const pos = ctx.world.getMut(selection, components.Position);
                    if (pos == null) {
                        break :blk;
                    }

                    const rot = ctx.world.getMut(selection, components.Rotation);
                    if (rot == null) {
                        break :blk;
                    }

                    const scale = ctx.world.getMut(selection, components.Scale);
                    if (scale == null) {
                        break :blk;
                    }

                    const bb = mesh.?.bounds.translate(transform.?.value);
                    gizmo.drawBoundingBox(bb) catch @panic("error");
                    gizmo.manipulate(&pos.?.value, &rot.?.value, &scale.?.value) catch @panic("error");
                },
                else => {},
            }
        }
        gizmo.endFrame();
    }
    c.ImGui_End();
}

fn sys(it: *ecs.Iter, matrices: []components.TransformMatrix, meshes: []components.Mesh, materials: []components.Material) void {
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
