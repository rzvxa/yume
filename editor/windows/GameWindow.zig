const c = @import("clibs");

const std = @import("std");

const gizmo = @import("../gizmo.zig");

const ecs = @import("yume").ecs;
const Vec3 = @import("yume").Vec3;
const Engine = @import("yume").VulkanEngine;
const GameApp = @import("yume").GameApp;
const Object = @import("yume").scene_graph.Object;
const components = @import("yume").components;
const AllocatedBuffer = @import("yume").AllocatedBuffer;

const Editor = @import("../Editor.zig");

const FrameData = struct {
    app: *GameApp,
    cmd: GameApp.RenderCommand,
    d: *Self,
    camera: ?*const components.Camera = null,
};

const Self = @This();

game_view_size: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),
game_window_rect: c.ImVec4 = std.mem.zeroInit(c.ImVec4, .{}),
is_game_window_focused: bool = false,

frame_userdata: FrameData = undefined,
camera_query: *ecs.Query,
render_system: ecs.Entity,

pub fn init(ctx: *GameApp) Self {
    return .{
        .camera_query = ctx.world.query(&std.mem.zeroInit(
            c.ecs_query_desc_t,
            .{ .terms = .{
                .{ .id = ecs.typeId(components.Camera) },
                .{ .id = ecs.typeId(components.Position) },
                .{ .id = ecs.typeId(components.Rotation) },
            } },
        )),
        .render_system = ctx.world.systemEx(.{
            .entity = ctx.world.create("Render System"),
            .query = std.mem.zeroInit(c.ecs_query_desc_t, .{ .terms = .{
                .{ .id = ecs.typeId(components.TransformMatrix) },
                .{ .id = ecs.typeId(components.Mesh) },
                .{ .id = ecs.typeId(components.Material) },
            } }),
            .callback = @ptrCast(&ecs.SystemImpl(renderSys).exec),
        }),
    };
}

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

                var iter = me.d.camera_query.iter();
                const aspect = me.d.game_view_size.x / me.d.game_view_size.y;
                while (c.ecs_query_next(&iter)) {
                    const cameras = ecs.field(&iter, components.Camera, @alignOf(components.Camera), 0).?;
                    const positions = ecs.field(&iter, components.Position, @alignOf(components.Position), 1).?;
                    const rotations = ecs.field(&iter, components.Rotation, @alignOf(components.Rotation), 2).?;
                    for (cameras, positions, rotations) |*camera, pos, rot| {
                        camera.updateMatrices(pos.value, rot.value, aspect);
                        var new_me = me.*;
                        new_me.camera = camera;
                        _ = c.ecs_run(iter.real_world, me.d.render_system, me.app.delta, &new_me);
                    }
                }

                c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = GameApp.window_extent,
                }});
            }
        }.f, &self.frame_userdata);
        c.ImDrawList_AddCallback(game_image, c.ImDrawCallback_ResetRenderState, null);
        if (!c.ecs_query_is_true(&self.camera_query.inner)) {
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

fn renderSys(it: *ecs.Iter, matrices: []components.TransformMatrix, meshes: []align(8) components.Mesh, materials: []align(8) components.Material) void {
    const me: *FrameData = @ptrCast(@alignCast(it.param));
    me.app.engine.drawObjects(
        me.cmd,
        matrices,
        meshes,
        materials,
        me.app.engine.camera_and_scene_buffer,
        me.app.engine.camera_and_scene_set,
        me.camera.?,
    );
}
