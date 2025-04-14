const c = @import("clibs");

const std = @import("std");

const gizmo = @import("../gizmo.zig");

const Vec3 = @import("yume").Vec3;
const Engine = @import("yume").VulkanEngine;
const GameApp = @import("yume").GameApp;
const Object = @import("yume").scene_graph.Object;
const Camera = @import("yume").Camera;
const AllocatedBuffer = @import("yume").AllocatedBuffer;

const Editor = @import("../Editor.zig");

const FrameData = struct { app: *GameApp, cmd: GameApp.RenderCommand, d: *Self };

const Self = @This();

game_view_size: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),
game_window_rect: c.ImVec4 = std.mem.zeroInit(c.ImVec4, .{}),
is_game_window_focused: bool = false,

frame_userdata: FrameData = undefined,

pub fn draw(self: *Self, cmd: Engine.RenderCommand, ctx: *GameApp) void {
    self.frame_userdata = FrameData{ .app = ctx, .cmd = cmd, .d = self };
    if (c.ImGui_Begin("Game", null, 0)) {
        self.is_game_window_focused = c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_None);
        const game_image = c.ImGui_GetWindowDrawList();
        self.game_view_size = c.ImGui_GetWindowSize();
        c.ImDrawList_AddCallback(game_image, extern struct {
            fn f(dl: [*c]const c.ImDrawList, dc: [*c]const c.ImDrawCmd) callconv(.C) void {
                _ = dl;
                const me: *FrameData = @alignCast(@ptrCast(dc.*.UserCallbackData));
                const cr = dc.*.ClipRect;
                me.d.game_window_rect = cr;
                const w = cr.z - cr.x;
                const h = cr.w - cr.y;

                me.app.engine.beginAdditiveRenderPass(me.cmd);

                c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                    .offset = .{ .x = @intFromFloat(cr.x), .y = @intFromFloat(cr.y) },
                    .extent = .{ .width = @intFromFloat(w), .height = @intFromFloat(h) },
                }});

                const vx = if (cr.x > 0) cr.x else cr.z - me.d.game_view_size.x;
                c.vkCmdSetViewport(me.cmd, 0, 1, &[_]c.VkViewport{.{
                    .x = vx,
                    .y = cr.y,
                    .width = me.d.game_view_size.x,
                    .height = me.d.game_view_size.y,
                    .minDepth = 0.0,
                    .maxDepth = 1.0,
                }});

                const aspect = me.d.game_view_size.x / me.d.game_view_size.y;
                if (me.app.scene.main_camera) |main_camera| {
                    main_camera.updateMatrices(
                        main_camera.object.transform.position(),
                        Vec3.ZERO,
                        aspect,
                    );
                    // me.app.engine.drawObjects(
                    //     me.cmd,
                    //     me.app.scene.renderables.items,
                    //     me.app.engine.camera_and_scene_buffer,
                    //     me.app.engine.camera_and_scene_set,
                    //     main_camera,
                    // );
                }

                _ = c.ecs_run(me.app.world.inner, Editor.render_system, me.app.delta, null);

                c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = GameApp.window_extent,
                }});
            }
        }.f, &self.frame_userdata);
        c.ImDrawList_AddCallback(game_image, c.ImDrawCallback_ResetRenderState, null);
        if (ctx.scene.main_camera == null) {
            const text = "No Camera";
            const size = c.ImGui_CalcTextSize(text);
            const avail = c.ImGui_GetContentRegionAvail();
            const style = c.ImGui_GetStyle();
            c.ImGui_SetCursorPos(c.ImVec2{
                .x = (avail.x - size.x) / 2,
                .y = (avail.y - size.y + style.*.WindowPadding.y) / 2,
            });
            c.ImGui_Text(text);
        }
    }
    c.ImGui_End();
}
