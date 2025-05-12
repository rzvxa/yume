const c = @import("clibs");

const std = @import("std");

const gizmo = @import("../gizmo.zig");

const ecs = @import("yume").ecs;
const Vec2 = @import("yume").Vec2;
const Vec3 = @import("yume").Vec3;
const Vec4 = @import("yume").Vec4;
const Quat = @import("yume").Quat;
const Mat4 = @import("yume").Mat4;
const Rect = @import("yume").Rect;
const Engine = @import("yume").VulkanEngine;
const GameApp = @import("yume").GameApp;
const components = @import("yume").ecs.components;
const AllocatedBuffer = @import("yume").AllocatedBuffer;
const GPULightData = Engine.GPUSceneData.GPULightData;

const MouseButton = @import("yume").inputs.MouseButton;

const Editor = @import("../Editor.zig");

const FrameData = struct {
    app: *GameApp,
    cmd: GameApp.RenderCommand,
    d: *Self,
    lights: []GPULightData = undefined,
};

const default_cam_distance = 10;
const default_cam_angle = Vec2.make(std.math.degreesToRadians(30), std.math.degreesToRadians(90));

const Self = @This();

camera: components.Camera = components.Camera.makePerspectiveCamera(.{
    .fovy_rad = std.math.degreesToRadians(70.0),
    .far = 200,
    .near = 0.1,
}),

camera_pos: Vec3 = Vec3.ZERO,
target_pos: Vec3 = Vec3.ZERO,
distance: f32 = default_cam_distance,

active_tool: gizmo.ManipulationTool = .move,
active_mode: gizmo.ManipulationMode = .global,

is_perspective: bool = true,
render_lights: bool = true,
is_lights_button_hovered: bool = false,

scene_window_rect: c.ImVec4 = std.mem.zeroInit(c.ImVec4, .{}),
scene_view_size: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),
is_focused: bool = false,
is_hovered: bool = false,

state: State = .idle,

editor_camera_and_scene_buffer: AllocatedBuffer = undefined,
editor_camera_and_scene_set: c.VkDescriptorSet = null,

frame_userdata: FrameData = undefined,
cast_query: *ecs.Query,
directional_light_query: *ecs.Query,
point_lights_query: *ecs.Query,
transform_query: *ecs.Query,
render_system: ecs.Entity,

on_draw_gizmos: *const fn (*anyopaque) void,
on_draw_gizmos_ctx: *anyopaque,

pub fn init(ctx: *GameApp, on_draw_gizmos: *const fn (*anyopaque) void, on_draw_gizmos_ctx: *anyopaque) Self {
    var self = Self{
        .cast_query = ctx.world.query(&std.mem.zeroInit(
            c.ecs_query_desc_t,
            .{ .terms = .{
                .{ .id = ecs.typeId(components.WorldTransform) },
                .{ .id = ecs.typeId(components.Mesh) },
            } },
        )),
        .directional_light_query = ctx.world.query(&std.mem.zeroInit(
            c.ecs_query_desc_t,
            .{ .terms = .{
                .{ .id = ecs.typeId(components.WorldTransform) },
                .{ .id = ecs.typeId(components.DirectionalLight) },
            } },
        )),
        .point_lights_query = ctx.world.query(&std.mem.zeroInit(
            c.ecs_query_desc_t,
            .{ .terms = .{
                .{ .id = ecs.typeId(components.WorldTransform) },
                .{ .id = ecs.typeId(components.PointLight) },
            } },
        )),
        .transform_query = ctx.world.query(&std.mem.zeroInit(
            c.ecs_query_desc_t,
            .{ .terms = .{
                .{ .id = ecs.typeId(components.WorldTransform) },
            } },
        )),
        .render_system = ctx.world.systemEx(&.{
            .entity = ctx.world.create("Editor Render System"),
            .query = std.mem.zeroInit(c.ecs_query_desc_t, .{ .terms = .{
                .{ .id = ecs.typeId(components.WorldTransform) },
                .{ .id = ecs.typeId(components.Mesh) },
                .{ .id = ecs.typeId(components.Material) },
            } }),
            .callback = @ptrCast(&ecs.SystemImpl(sys).exec),
        }),
        .on_draw_gizmos = on_draw_gizmos,
        .on_draw_gizmos_ctx = on_draw_gizmos_ctx,
    };
    self.focus(Vec3.ZERO, default_cam_distance);
    return self;
}

pub fn deinit(self: *Self) void {
    self.transform_query.deinit();
    self.directional_light_query.deinit();
    self.point_lights_query.deinit();
    self.cast_query.deinit();
}

pub fn draw(self: *Self, cmd: Engine.RenderCommand, ctx: *GameApp) !void {
    self.frame_userdata = FrameData{ .app = ctx, .cmd = cmd, .d = self };
    if (c.ImGui_Begin("Scene", null, c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoNav | c.ImGuiWindowFlags_NoScrollbar | c.ImGuiWindowFlags_NoScrollWithMouse)) {
        self.is_focused = c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_None);
        self.is_hovered = c.ImGui_IsWindowHovered(c.ImGuiFocusedFlags_None);
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
                me.d.camera.updatePerspectiveProjection(aspect);
                me.d.camera.updateViewProjection();
                _ = c.ecs_run(me.app.world.inner, me.d.render_system, me.app.delta, me);

                const window_extent = me.app.windowExtent();
                c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = .{ .width = @intCast(window_extent.x), .height = @intCast(window_extent.y) },
                }});
            }
        }.f, &self.frame_userdata);
        c.ImDrawList_AddCallback(editor_image, c.ImDrawCallback_ResetRenderState, null);

        const icon_sz = c.ImVec2{ .x = 16, .y = 16 };
        const normal_col = c.ImGui_GetStyle().*.Colors[c.ImGuiCol_Button];
        const active_col = c.ImGui_GetStyle().*.Colors[c.ImGuiCol_ButtonHovered];
        if (c.ImGui_BeginChildFrame(c.ImGui_GetID("##toolbox"), c.ImVec2{
            .x = icon_sz.x + (c.ImGui_GetStyle().*.FramePadding.x * 4),
            .y = ((icon_sz.y + c.ImGui_GetStyle().*.FramePadding.y * 4) * 6) - 2,
        })) {
            var clicked = false;
            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.active_tool == .move) active_col else normal_col,
            );

            clicked = c.ImGui_ImageButton(
                "##move-tool",
                try Editor.getImGuiTexture("editor://icons/move-tool.png"),
                icon_sz,
            );
            c.ImGui_PopStyleColor();
            if (clicked) {
                self.active_tool = .move;
            }

            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.active_tool == .rotate) active_col else normal_col,
            );
            clicked = c.ImGui_ImageButton(
                "##rotate-tool",
                try Editor.getImGuiTexture("editor://icons/rotate-tool.png"),
                icon_sz,
            );
            c.ImGui_PopStyleColor();
            if (clicked) {
                self.active_tool = .rotate;
            }

            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.active_tool == .scale) active_col else normal_col,
            );
            clicked = c.ImGui_ImageButton(
                "##scale-tool",
                try Editor.getImGuiTexture("editor://icons/scale-tool.png"),
                icon_sz,
            );
            c.ImGui_PopStyleColor();
            if (clicked) {
                self.active_tool = .scale;
            }

            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.active_tool == .transform) active_col else normal_col,
            );
            clicked = c.ImGui_ImageButton(
                "##transform-tool",
                try Editor.getImGuiTexture("editor://icons/transform-tool.png"),
                icon_sz,
            );
            c.ImGui_PopStyleColor();
            if (clicked) {
                self.active_tool = .transform;
            }

            c.ImGui_Separator();

            const styles = c.ImGui_GetStyle();
            const letter_sz = c.ImVec2{
                .x = icon_sz.x + styles.*.FramePadding.x * 2,
                .y = icon_sz.y + styles.*.FramePadding.y * 2,
            };

            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.active_mode == .global) active_col else normal_col,
            );
            clicked = c.ImGui_ButtonEx("G##global-mode", letter_sz);
            c.ImGui_PopStyleColor();
            if (clicked) {
                self.active_mode = .global;
            }

            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.active_mode == .local) active_col else normal_col,
            );
            clicked = c.ImGui_ButtonEx("L##local-mode", letter_sz);
            c.ImGui_PopStyleColor();
            if (clicked) {
                self.active_mode = .local;
            }

            c.ImGui_EndChildFrame();
        }

        gizmo.newFrame(editor_image, &self.camera.view, self.camera.projection, self.distance, .{
            .x = self.scene_window_rect.x,
            .y = self.scene_window_rect.y,
            .width = self.scene_view_size.x,
            .height = self.scene_view_size.y,
        });

        {
            const right = self.scene_view_size.x;
            const cursor = c.ImGui_GetCursorPos();
            c.ImGui_SetCursorPos(.{ .x = right - 90, .y = 128 });
            c.ImGui_TextColored(
                c.ImVec4{
                    .x = 0.64,
                    .y = 0.64,
                    .z = 0.64,
                    .w = if (self.is_lights_button_hovered) 0.8 else 0.5,
                },
                if (self.render_lights) "Lights: On" else "Lights: Off",
            );
            self.is_lights_button_hovered = c.ImGui_IsItemHovered(0);
            if (c.ImGui_IsItemClicked()) {
                self.render_lights = !self.render_lights;
            }
            c.ImGui_SetCursorPos(cursor);
        }

        blk: {
            switch (Editor.instance().selection) {
                .entity => |selection| {
                    const local_transform = ctx.world.getMut(selection, components.LocalTransform) orelse break :blk;

                    const world_transform = ctx.world.getMut(selection, components.WorldTransform).?;

                    if (c.ImGui_IsKeyPressed(c.ImGuiKey_F)) {
                        self.focus(world_transform.position(), default_cam_distance);
                    }

                    if (ctx.world.get(selection, components.Mesh)) |mesh| {
                        try gizmo.drawBoundingBoxCorners(mesh.bounds, world_transform.matrix);
                    }
                    var selection_id_buf = std.mem.zeroes([19:0]u8);
                    c.ImGuizmo_PushID_Str((try std.fmt.bufPrintZ(&selection_id_buf, "{d}", .{selection})).ptr);
                    if (try gizmo.editTransform(
                        &world_transform.matrix,
                        &local_transform.matrix,
                        self.active_tool,
                        self.active_mode,
                    )) {
                        ctx.world.modified(selection, components.LocalTransform);
                    }
                    c.ImGuizmo_PopID();
                },
                else => {},
            }
        }

        {
            self.on_draw_gizmos(self.on_draw_gizmos_ctx);
            var iter = self.transform_query.iter();
            while (iter.next()) {
                const transforms = ecs.field(&iter, components.WorldTransform, 0).?;
                for (transforms, 0..) |transform, i| {
                    const entity = iter.inner.entities[i];
                    var entity_id_buf = std.mem.zeroes([19:0]u8);
                    c.ImGui_PushID((try std.fmt.bufPrintZ(&entity_id_buf, "{d}", .{entity})).ptr);
                    for (try ctx.world.getType(entity)) |id| {
                        if (ecs.isPair(id)) {
                            continue;
                        }
                        const comp_id = id & ecs.masks.component;
                        const comp_path = try ctx.world.getPathAlloc(comp_id, ctx.allocator);
                        defer ctx.allocator.free(comp_path);

                        const def = ctx.components.get(comp_path) orelse continue;
                        if (def.billboard) |billboard| {
                            var id_buf = std.mem.zeroes([19:0]u8);
                            if (gizmo.drawBillboardIcon(
                                (try std.fmt.bufPrintZ(&id_buf, "{d}", .{comp_id})).ptr,
                                transform.position(),
                                try Editor.getImGuiTexture(std.mem.span(billboard)),
                                32,
                            )) {
                                Editor.instance().selection = .{ .entity = entity };
                            }
                        }
                    }

                    c.ImGui_PopID();
                }
            }
        }
        gizmo.endFrame();
    }
    c.ImGui_End();
}

pub fn update(self: *Self, ctx: *GameApp) !void {
    if (!self.is_hovered and !self.state.inUse()) {
        return;
    }

    var input: Vec3 = Vec3.make(0, 0, 0);
    var input_rot: Vec3 = Vec3.make(0, 0, 0);

    const inversed = self.camera.view.inverse() catch Mat4.IDENTITY;
    var decomposed = inversed.decompose() catch Mat4.Decomposed.IDENTITY;
    self.camera_pos = decomposed.translation;
    const basis = decomposed.rotation.toBasisVectors();

    const left = basis.right.mulf(-1);
    const up = basis.up;
    const forward = basis.forward.mulf(-1);

    // handle translation inputs (W, A, S, D) relative to view
    // we don't apply it right away.
    const wasd = blk: {
        var wasd = Vec3.ZERO;
        wasd = wasd.add(forward.mulf(if (Editor.inputs.isKeyDown(.w)) 1 else 0));
        wasd = wasd.sub(forward.mulf(if (Editor.inputs.isKeyDown(.s)) 1 else 0));
        wasd = wasd.add(left.mulf(if (Editor.inputs.isKeyDown(.a)) 1 else 0));
        wasd = wasd.sub(left.mulf(if (Editor.inputs.isKeyDown(.d)) 1 else 0));
        wasd = wasd.add(up.mulf(if (Editor.inputs.isKeyDown(.e)) 1 else 0));
        wasd = wasd.sub(up.mulf(if (Editor.inputs.isKeyDown(.q)) 1 else 0));
        wasd = wasd.mulf(5);
        break :blk wasd;
    };

    var in_use: bool = false;

    var new_state = self.state;
    switch (self.state) {
        .idle => {
            if (Editor.inputs.isMouseButtonPressed(.right)) {
                new_state = .free;
            } else if (Editor.inputs.isMouseButtonPressed(.middle)) {
                if (Editor.inputs.isKeyDown(.left_shift)) {
                    new_state = .pan;
                } else {
                    new_state = .orbit;
                }
            } else { // idle scroll zoom
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

                if (Editor.inputs.isKeyPressed(.q)) {
                    self.active_tool = .move;
                } else if (Editor.inputs.isKeyPressed(.w)) {
                    self.active_tool = .rotate;
                } else if (Editor.inputs.isKeyPressed(.e)) {
                    self.active_tool = .scale;
                } else if (Editor.inputs.isKeyPressed(.r)) {
                    self.active_tool = .transform;
                }
            }
        },
        .free => {
            if (Editor.inputs.isMouseButtonUp(.right)) {
                new_state = .idle;
            }

            in_use = true;
            Editor.inputs.setRelativeMouseMode(true);
            const mouse_delta = Editor.inputs.mouseRelative().mulf(0.5);
            input_rot.y -= mouse_delta.x;
            input_rot.x -= mouse_delta.y;
            input = input.add(wasd);
        },
        .pan => {
            // we keep paning even if shift is released
            // user should release the mouse botten in order to release the pan
            if (Editor.inputs.isMouseButtonUp(.middle)) {
                new_state = .idle;
            }

            in_use = true;
            const mouse_delta = Editor.inputs.mouseDelta();
            input = input.add(left.mulf(mouse_delta.x));
            input = input.add(up.mulf(mouse_delta.y));
        },
        .orbit => {
            if (Editor.inputs.isMouseButtonUp(.middle)) {
                new_state = .idle;
            }

            in_use = true;
            const orbit_delta = Editor.inputs.mouseRelative();
            const sensitivity: f32 = 0.005;

            self.target_pos = self.camera_pos.add(forward.mulf(self.distance));

            const offset = self.camera_pos.sub(self.target_pos);
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

            const cos_pitch = std.math.cos(clamped_pitch);
            const sin_pitch = std.math.sin(clamped_pitch);
            const cos_yaw = std.math.cos(new_yaw);
            const sin_yaw = std.math.sin(new_yaw);
            const new_eye = Vec3.make(
                self.target_pos.x + current_distance * cos_pitch * sin_yaw,
                self.target_pos.y + current_distance * sin_pitch,
                self.target_pos.z + current_distance * cos_pitch * cos_yaw,
            );

            self.camera.view = Mat4.lookAt(new_eye, self.target_pos, Vec3.UP);
            decomposed = (try self.camera.view.inverse()).decompose() catch Mat4.Decomposed.IDENTITY;
            input = input.add(wasd);
        },
    }

    self.state = new_state;

    if (!in_use) {
        if (self.is_hovered and !gizmo.isOverAny()) {
            if (Editor.inputs.isMouseButtonPressed(.left)) {
                const mouse_pos = Editor.inputs.mousePos();
                const ray = screenPosToRay(mouse_pos, self.camera, .{
                    .x = self.scene_window_rect.x,
                    .y = self.scene_window_rect.y,
                    .width = self.scene_view_size.x,
                    .height = self.scene_view_size.y,
                });
                const hits = try self.raycast(ray, 200, ctx.allocator);
                defer ctx.allocator.free(hits);
                if (hits.len > 0) {
                    Editor.instance().selection = .{ .entity = hits[0].entity };
                } else {
                    Editor.instance().selection = .{ .none = {} };
                }
            }
        }
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

fn sys(it: *ecs.Iter, transforms: []components.WorldTransform, meshes: []components.Mesh, materials: []components.Material) void {
    const me: *FrameData = @ptrCast(@alignCast(it.param));

    const directional_light: GPULightData = blk: {
        var iter = me.d.directional_light_query.iter();
        while (iter.next()) {
            const wts = ecs.field(&iter, components.WorldTransform, 0).?;
            const lights = ecs.field(&iter, components.DirectionalLight, 1).?;
            for (lights, wts) |light, transform| {
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
        var lights = std.ArrayList(GPULightData).init(a);
        while (iter.next()) {
            const wts = ecs.field(&iter, components.WorldTransform, 0).?;
            const point_lights = ecs.field(&iter, components.PointLight, 1).?;
            for (point_lights, wts) |light, transform| {
                lights.append(.{
                    .pos = transform.position(),
                    .color = light.color,
                    .intensity = light.intensity,
                    .range = light.range,
                }) catch @panic("OOM");
            }
        }
        break :blk lights;
    };
    defer point_lights.deinit();

    std.mem.sort(GPULightData, point_lights.items, me.d.camera_pos, struct {
        pub fn f(cam_pos: Vec3, a: GPULightData, b: GPULightData) bool {
            return a.pos.distanceTo(cam_pos) < b.pos.distanceTo(cam_pos);
        }
    }.f);

    var lights = std.mem.zeroes([4]Engine.GPUSceneData.GPULightData);
    std.debug.assert(point_lights.items.len < 4);
    if (me.d.render_lights) {
        @memcpy(lights[0..point_lights.items.len], point_lights.items);
    }
    me.app.engine.drawObjects(
        me.cmd,
        .{
            .transforms = transforms,
            .meshes = meshes,
            .materials = materials,
            .ubo_buf = me.d.editor_camera_and_scene_buffer,
            .ubo_set = me.d.editor_camera_and_scene_set,
            .cam = &me.d.camera,
            .cam_pos = me.d.camera_pos,
            .directional_light = if (me.d.render_lights) directional_light else std.mem.zeroes(Engine.GPUSceneData.GPULightData),
            .point_lights = lights,
        },
    );
}

const Raycast = struct {
    pub const Hit = struct {
        entity: ecs.Entity,
        position: Vec3,
    };

    origin: Vec3,
    dir: Vec3,
};

fn raycast(self: *Self, ray: Raycast, distance: f32, allocator: std.mem.Allocator) ![]Raycast.Hit {
    var intersections = std.ArrayList(Raycast.Hit).init(allocator);

    var iter = self.cast_query.iter();
    while (iter.next()) {
        const transforms_ptr = ecs.field(&iter, components.WorldTransform, 0).?;
        const meshes_ptr = ecs.field(&iter, components.Mesh, 1).?;
        for (iter.inner.entities, meshes_ptr, transforms_ptr) |entity, *mesh, transform| {
            const bb = mesh.bounds;

            // transform the ray into the mesh's local space.
            const inv = transform.matrix.inverse() catch Mat4.IDENTITY;
            const local_origin = inv.mulVec3(ray.origin);

            const world_target = ray.origin.add(ray.dir);
            const local_target = inv.mulVec3(world_target);
            const local_dir = local_target.sub(local_origin).normalized();

            // Perform ray vs. AABB test in local space.
            const maybeT = rayAABB(local_origin, local_dir, bb.mins, bb.maxs);
            if (maybeT) |t_local| {
                if (t_local >= 0) {
                    const localHit = local_origin.add(local_dir.mulf(t_local));
                    const worldHit = transform.matrix.mulVec3(localHit);
                    if (ray.origin.distanceTo(worldHit) <= distance) {
                        try intersections.append(.{ .entity = entity, .position = worldHit });
                    }
                }
            }
        }
    }

    const slice = try intersections.toOwnedSlice();
    std.mem.sort(Raycast.Hit, slice, ray.origin, struct {
        fn f(org: Vec3, a: Raycast.Hit, b: Raycast.Hit) bool {
            return std.sort.desc(f32)({}, a.position.distanceTo(org), b.position.distanceTo(org));
        }
    }.f);
    return slice;
}

/// Ray vs. AABB intersection in local space.
/// Returns the entry parameter t along the ray (in local space) if the ray intersects the box; otherwise, returns null.
fn rayAABB(origin: Vec3, dir: Vec3, bb_mins: Vec3, bb_maxs: Vec3) ?f32 {
    var tmin: f32 = -std.math.inf(f32);
    var tmax: f32 = std.math.inf(f32);

    // X-axis:
    if (@abs(dir.x) < 0.00001) {
        if (origin.x < bb_mins.x or origin.x > bb_maxs.x)
            return null;
    } else {
        const inv = 1.0 / dir.x;
        const t1 = (bb_mins.x - origin.x) * inv;
        const t2 = (bb_maxs.x - origin.x) * inv;
        const t_near = @min(t1, t2);
        const t_far = @max(t1, t2);
        if (t_near > tmin) tmin = t_near;
        if (t_far < tmax) tmax = t_far;
        if (tmin > tmax)
            return null;
    }

    // Y-axis:
    if (@abs(dir.y) < 0.00001) {
        if (origin.y < bb_mins.y or origin.y > bb_maxs.y)
            return null;
    } else {
        const inv = 1.0 / dir.y;
        const t1 = (bb_mins.y - origin.y) * inv;
        const t2 = (bb_maxs.y - origin.y) * inv;
        const t_near = @min(t1, t2);
        const t_far = @max(t1, t2);
        if (t_near > tmin) tmin = t_near;
        if (t_far < tmax) tmax = t_far;
        if (tmin > tmax)
            return null;
    }

    // Z-axis:
    if (@abs(dir.z) < 0.00001) {
        if (origin.z < bb_mins.z or origin.z > bb_maxs.z)
            return null;
    } else {
        const inv = 1.0 / dir.z;
        const t1 = (bb_mins.z - origin.z) * inv;
        const t2 = (bb_maxs.z - origin.z) * inv;
        const t_near = @min(t1, t2);
        const t_far = @max(t1, t2);
        if (t_near > tmin) tmin = t_near;
        if (t_far < tmax) tmax = t_far;
        if (tmin > tmax)
            return null;
    }

    return tmin;
}

fn screenPosToRay(mousePos: Vec2, camera: components.Camera, viewport: Rect) Raycast {
    const ndc_x = ((mousePos.x - viewport.x) / viewport.width) * 2.0 - 1.0;
    const ndc_y = ((mousePos.y - viewport.y) / viewport.height) * 2.0 - 1.0;

    const ndc_near = Vec4.make(ndc_x, ndc_y, 0.0, 1.0);
    const ndc_far = Vec4.make(ndc_x, ndc_y, 1.0, 1.0);

    const invVP = camera.view_projection.inverse() catch Mat4.IDENTITY;

    const world_near4 = invVP.mulVec4(ndc_near);
    const world_far4 = invVP.mulVec4(ndc_far);

    // Perspective divide to get 3D coordinates.
    const world_near = Vec3.make(world_near4.x / world_near4.w, world_near4.y / world_near4.w, world_near4.z / world_near4.w);
    const world_far = Vec3.make(world_far4.x / world_far4.w, world_far4.y / world_far4.w, world_far4.z / world_far4.w);

    // The ray origin is the near point; ray direction is from near to far.
    const dir = world_far.sub(world_near).normalized();
    return .{ .origin = world_near, .dir = dir };
}

fn computeOrbitEye(target: Vec3, orbit_angles: Vec2, distance: f32) Vec3 {
    // Spherical coordinate conversion.
    const cos_pitch = std.math.cos(orbit_angles.x);
    const sin_pitch = std.math.sin(orbit_angles.x);
    const cos_yaw = std.math.cos(orbit_angles.y);
    const sin_yaw = std.math.sin(orbit_angles.y);

    return Vec3.make(
        target.x + distance * cos_pitch * sin_yaw,
        target.y + distance * sin_pitch,
        target.z + distance * cos_pitch * cos_yaw,
    );
}

const State = enum {
    idle,
    free,
    pan,
    orbit,

    fn inUse(s: State) bool {
        return s != .idle;
    }
};
