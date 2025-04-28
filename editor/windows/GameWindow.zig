const c = @import("clibs");

const std = @import("std");
const log = std.log.scoped(.GameWindow);

const gizmo = @import("../gizmo.zig");

const ecs = @import("yume").ecs;
const components = ecs.components;

const Vec3 = @import("yume").Vec3;
const Engine = @import("yume").VulkanEngine;
const GameApp = @import("yume").GameApp;
const AllocatedBuffer = @import("yume").AllocatedBuffer;
const GPULightData = Engine.GPUSceneData.GPULightData;

const Editor = @import("../Editor.zig");

const FrameData = struct {
    app: *GameApp,
    cmd: GameApp.RenderCommand,
    d: *Self,
    camera: ?*const components.Camera = null,
    camera_pos: Vec3 = Vec3.ZERO,
    directional_light: GPULightData = undefined,
    point_lights: []GPULightData = undefined,
};

const Self = @This();

game_view_size: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),
game_window_rect: c.ImVec4 = std.mem.zeroInit(c.ImVec4, .{}),
is_game_window_focused: bool = false,

frame_userdata: FrameData = undefined,
camera_query: *ecs.Query,
directional_light_query: *ecs.Query,
point_lights_query: *ecs.Query,
render_system: ecs.Entity,

pub fn init(ctx: *GameApp) Self {
    return .{
        .camera_query = ctx.world.query(&std.mem.zeroInit(
            c.ecs_query_desc_t,
            .{ .terms = .{
                .{ .id = ecs.typeId(components.Transform) },
                .{ .id = ecs.typeId(components.Camera) },
            } },
        )),
        .directional_light_query = ctx.world.query(&std.mem.zeroInit(
            c.ecs_query_desc_t,
            .{ .terms = .{
                .{ .id = ecs.typeId(components.Transform) },
                .{ .id = ecs.typeId(components.DirectionalLight) },
            } },
        )),
        .point_lights_query = ctx.world.query(&std.mem.zeroInit(
            c.ecs_query_desc_t,
            .{ .terms = .{
                .{ .id = ecs.typeId(components.Transform) },
                .{ .id = ecs.typeId(components.PointLight) },
            } },
        )),
        .render_system = ctx.world.systemEx(&.{
            .entity = ctx.world.create("Render System"),
            .query = std.mem.zeroInit(c.ecs_query_desc_t, .{ .terms = .{
                .{ .id = ecs.typeId(components.Transform) },
                .{ .id = ecs.typeId(components.Mesh) },
                .{ .id = ecs.typeId(components.Material) },
            } }),
            .callback = @ptrCast(&ecs.SystemImpl(renderSys).exec),
        }),
    };
}

pub fn deinit(self: *Self) void {
    self.directional_light_query.deinit();
    self.point_lights_query.deinit();
    self.camera_query.deinit();
}

pub fn draw(self: *Self, cmd: Engine.RenderCommand, ctx: *GameApp) void {
    self.frame_userdata = FrameData{ .app = ctx, .cmd = cmd, .d = self };
    if (c.ImGui_Begin("Game", null, c.ImGuiWindowFlags_NoCollapse)) {
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

                const directional_light: GPULightData = blk: {
                    var iter = me.d.directional_light_query.iter();
                    while (iter.next()) {
                        const transforms = ecs.field(&iter, components.Transform, @alignOf(components.Transform), 0).?;
                        const lights = ecs.field(&iter, components.DirectionalLight, @alignOf(components.DirectionalLight), 1).?;
                        for (lights, transforms) |light, transform| {
                            iter.deinit();
                            break :blk .{
                                .pos = transform.rotation().toBasisVectors().forward,
                                .color = light.color,
                                .intensity = light.intensity,
                                .range = 0,
                            };
                        }
                    }
                    break :blk std.mem.zeroes(GPULightData);
                };

                const point_lights = blk: {
                    var sfa = std.heap.stackFallback(512, me.app.allocator);
                    const a = sfa.get();
                    var iter = me.d.point_lights_query.iter();
                    var point_lights = std.ArrayList(GPULightData).init(a);
                    while (iter.next()) {
                        const transforms = ecs.field(&iter, components.Transform, @alignOf(components.Transform), 0).?;
                        const pls = ecs.field(&iter, components.PointLight, @alignOf(components.PointLight), 1).?;
                        for (pls, transforms) |light, transform| {
                            point_lights.append(.{
                                .pos = transform.position(),
                                .color = light.color,
                                .intensity = light.intensity,
                                .range = light.range,
                            }) catch @panic("OOM");
                        }
                    }
                    break :blk point_lights;
                };
                defer point_lights.deinit();

                var iter = me.d.camera_query.iter();
                const aspect = me.d.game_view_size.x / me.d.game_view_size.y;
                while (iter.next()) {
                    const transforms = ecs.field(&iter, components.Transform, @alignOf(components.Transform), 0).?;
                    const cameras = ecs.field(&iter, components.Camera, @alignOf(components.Camera), 1).?;
                    for (cameras, transforms) |*camera, transform| {
                        const decomposed = transform.decompose();
                        camera.updateMatrices(decomposed.translation, decomposed.rotation.toEuler(), aspect);

                        std.mem.sort(GPULightData, point_lights.items, decomposed.translation, struct {
                            pub fn f(cam_pos: Vec3, a: GPULightData, b: GPULightData) bool {
                                return a.pos.distanceTo(cam_pos) < b.pos.distanceTo(cam_pos);
                            }
                        }.f);

                        var new_me = me.*;
                        new_me.camera = camera;
                        new_me.camera_pos = transform.position();
                        new_me.directional_light = directional_light;
                        new_me.point_lights = point_lights.items;
                        _ = c.ecs_run(iter.inner.real_world, me.d.render_system, me.app.delta, &new_me);
                    }
                }

                c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = GameApp.window_extent,
                }});
            }
        }.f, &self.frame_userdata);
        c.ImDrawList_AddCallback(game_image, c.ImDrawCallback_ResetRenderState, null);
        if (!self.camera_query.isTrue()) {
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

fn renderSys(it: *ecs.Iter, matrices: []components.Transform, meshes: []components.Mesh, materials: []components.Material) void {
    const me: *FrameData = @ptrCast(@alignCast(it.param));
    var point_lights = std.mem.zeroes([4]Engine.GPUSceneData.GPULightData);
    std.debug.assert(me.point_lights.len < 4);
    @memcpy(point_lights[0..me.point_lights.len], me.point_lights);
    me.app.engine.drawObjects(
        me.cmd,
        .{
            .matrices = matrices,
            .meshes = meshes,
            .materials = materials,
            .ubo_buf = me.app.engine.camera_and_scene_buffer,
            .ubo_set = me.app.engine.camera_and_scene_set,
            .cam = me.camera.?,
            .cam_pos = me.camera_pos,
            .directional_light = me.directional_light,
            .point_lights = point_lights,
        },
    );
}
