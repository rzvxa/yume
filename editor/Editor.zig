const c = @import("clibs");

const std = @import("std");

const gizmo = @import("gizmo.zig");

const check_vk = @import("yume").vki.check_vk;

const textures = @import("yume").textures;
const Texture = textures.Texture;

const Camera = @import("yume").Camera;
const Scene = @import("yume").scene_graph.Scene;
const Object = @import("yume").scene_graph.Object;
const MeshRenderer = @import("yume").VulkanEngine.MeshRenderer;
const ScanCode = @import("yume").inputs.ScanCode;
const MouseButton = @import("yume").inputs.MouseButton;
const InputsContext = @import("yume").inputs.InputContext;

const GameApp = @import("yume").GameApp;
const Vec3 = @import("yume").math3d.Vec3;
const Vec4 = @import("yume").math3d.Vec4;
const Quat = @import("yume").math3d.Quat;
const Mat4 = @import("yume").math3d.Mat4;
const AllocatedBuffer = @import("yume").AllocatedBuffer;
const FRAME_OVERLAP = @import("yume").FRAME_OVERLAP;
const GPUCameraData = @import("yume").GPUCameraData;
const GPUSceneData = @import("yume").GPUSceneData;
const VmaImageDeleter = @import("yume").VmaImageDeleter;
const VmaBufferDeleter = @import("yume").VmaBufferDeleter;
const VulkanDeleter = @import("yume").VulkanDeleter;

const Engine = @import("yume").VulkanEngine;
const Self = @This();

inputs: InputsContext = .{},

play: bool = false,
imgui_demo_open: bool = false,

dockspace_flags: c.ImGuiDockNodeFlags = 0,

editor_camera_and_scene_buffer: AllocatedBuffer = undefined,
editor_camera_and_scene_set: c.VkDescriptorSet = null,

camera_pos: Vec3 = Vec3.make(-5.0, 3.0, -10.0),
camera_rot: Vec3 = Vec3.make(0, 0, 0),
camera_input: Vec3 = Vec3.make(0, 0, 0),
camera_input_rot: Vec3 = Vec3.make(0, 0, 0),

camera_view_inv: Mat4 = Mat4.IDENTITY,
camera: Camera = Camera.makePerspectiveCamera(.{
    .fovy_rad = std.math.degreesToRadians(70.0),
    .far = 200,
    .near = 0.1,
}),

game_view_size: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),
game_window_rect: c.ImVec4 = std.mem.zeroInit(c.ImVec4, .{}),
is_game_window_focused: bool = false,

scene_view_size: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),
scene_window_rect: c.ImVec4 = std.mem.zeroInit(c.ImVec4, .{}),
is_scene_window_focused: bool = false,

first_time: bool = true,

// assets

play_icon_ds: c.VkDescriptorSet = undefined,
pause_icon_ds: c.VkDescriptorSet = undefined,
stop_icon_ds: c.VkDescriptorSet = undefined,
fast_forward_icon_ds: c.VkDescriptorSet = undefined,

pub fn init(ctx: *GameApp) Self {
    var self = Self{};
    self.init_descriptors(&ctx.engine);
    self.init_imgui(&ctx.engine);
    var scene = Scene.init(ctx.allocator) catch @panic("OOM");

    {
        const parent = scene.newObject(.{
            .name = "Apes Together Strong!",
            .transform = Mat4.translation(Vec3.make(0, 3, 0)),
        }) catch @panic("OOM");
        var monkey = scene.newObject(.{
            .name = "Monkey",
            .transform = Mat4.translation(Vec3.make(-5, 3, 0)),
        }) catch @panic("OOM");
        monkey.addComponent(MeshRenderer, .{
            .mesh = ctx.engine.meshes.getPtr("monkey") orelse @panic("Failed to get monkey mesh"),
            .material = ctx.engine.materials.getPtr("default_mesh") orelse @panic("Failed to get default mesh material"),
        });
        monkey.setParent(parent);

        const empire = scene.newObject(.{
            .name = "Lost Empire",
            .transform = Mat4.translation(Vec3.make(5.0, -10.0, 0.0)),
        }) catch @panic("OOM");
        var empire_material = ctx.engine.materials.getPtr("textured_mesh") orelse @panic("Failed to get default mesh material");

        // Allocate descriptor set for signle-texture to use on the material
        const descriptor_set_alloc_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = ctx.engine.descriptor_pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &ctx.engine.single_texture_set_layout,
        });

        check_vk(c.vkAllocateDescriptorSets(ctx.engine.device, &descriptor_set_alloc_info, &empire_material.texture_set)) catch @panic("Failed to allocate descriptor set");

        // Sampler
        const sampler_ci = std.mem.zeroInit(c.VkSamplerCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = c.VK_FILTER_NEAREST,
            .minFilter = c.VK_FILTER_NEAREST,
            .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        });

        var sampler: c.VkSampler = undefined;
        check_vk(c.vkCreateSampler(ctx.engine.device, &sampler_ci, Engine.vk_alloc_cbs, &sampler)) catch @panic("Failed to create sampler");
        ctx.engine.deletion_queue.append(VulkanDeleter.make(sampler, c.vkDestroySampler)) catch @panic("Out of memory");

        const lost_empire_tex = (ctx.engine.textures.get("empire_diffuse") orelse @panic("Failed to get empire texture"));

        const descriptor_image_info = std.mem.zeroInit(c.VkDescriptorImageInfo, .{
            .sampler = sampler,
            .imageView = lost_empire_tex.image_view,
            .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        });

        const write_descriptor_set = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = empire_material.texture_set,
            .dstBinding = 0,
            .descriptorCount = 1,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &descriptor_image_info,
        });

        c.vkUpdateDescriptorSets(ctx.engine.device, 1, &write_descriptor_set, 0, null);

        empire.addComponent(MeshRenderer, .{
            .mesh = ctx.engine.meshes.getPtr("lost_empire") orelse @panic("Failed to get triangle mesh"),
            .material = empire_material,
        });
    }
    ctx.engine.loadScene(scene);
    return self;
}

pub fn deinit(_: *Self, ctx: *GameApp) void {
    check_vk(c.vkDeviceWaitIdle(ctx.engine.device)) catch @panic("Failed to wait for device idle");
    c.cImGui_ImplVulkan_Shutdown();
}

pub fn newFrame(self: *Self, _: *GameApp) void {
    self.inputs.clear();
}

pub fn processEvent(self: *Self, ctx: *GameApp, event: *c.SDL_Event) bool {
    _ = c.cImGui_ImplSDL3_ProcessEvent(event);
    switch (event.type) {
        c.SDL_EVENT_KEY_UP => {
            if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) {
                c.ImGui_FocusWindow(null, c.ImGuiFocusRequestFlags_None);
            }
        },
        c.SDL_EVENT_QUIT => return false,
        else => {},
    }
    if (self.is_game_window_focused) {
        ctx.inputs.push(event);
    } else if (self.is_scene_window_focused) {
        self.inputs.push(event);
    }

    return true;
}

fn isInGameView(self: *Self, pos: c.ImVec2) bool {
    return (pos.x > self.game_window_rect.x and pos.x < self.game_window_rect.z) and
        (pos.y > self.game_window_rect.y and pos.y < self.game_window_rect.w);
}

fn isInSceneView(self: *Self, pos: c.ImVec2) bool {
    return (pos.x > self.scene_window_rect.x and pos.x < self.scene_window_rect.z) and
        (pos.y > self.scene_window_rect.y and pos.y < self.scene_window_rect.w);
}

pub fn update(self: *Self, ctx: *GameApp) void {
    var input: Vec3 = Vec3.make(0, 0, 0);
    var input_rot: Vec3 = Vec3.make(0, 0, 0);

    // Create rotation quaternion
    const rot_x = Quat.fromAxisAngle(Vec3.make(1.0, 0.0, 0.0), self.camera_rot.x);
    const rot_y = Quat.fromAxisAngle(Vec3.make(0.0, 1.0, 0.0), self.camera_rot.y);
    const rot_z = Quat.fromAxisAngle(Vec3.make(0.0, 0.0, 1.0), self.camera_rot.z);
    const rot_quat = rot_z.mul(rot_y).mul(rot_x);

    // Calculate direction vectors
    const forward = rot_quat.mulVec3(Vec3.make(0, 0, 1)).normalized();
    const left = rot_quat.mulVec3(Vec3.make(-1, 0, 0)).normalized();
    const up = Vec3.cross(left, forward).normalized();

    if (self.inputs.isMouseButtonDown(MouseButton.Middle)) {
        self.inputs.setRelativeMouseMode(true);
        // Shift + MMB for panning
        if (self.inputs.isKeyDown(ScanCode.LeftShift)) {
            const mouse_delta = self.inputs.mouseDelta();
            input = input.add(left.mulf(mouse_delta.x));
            input = input.add(up.mulf(mouse_delta.y));
        } else { // Camera rotation handling (MMB for orbiting)
            const mouse_delta = self.inputs.mouseRelative();
            input_rot.y += mouse_delta.x;
            input_rot.x += mouse_delta.y;
        }
        // Handle translation inputs (W, A, S, D for panning) relative to view
        input = input.add(forward.mulf(if (self.inputs.isKeyDown(ScanCode.W)) 1 else 0));
        input = input.sub(forward.mulf(if (self.inputs.isKeyDown(ScanCode.S)) 1 else 0));
        input = input.add(left.mulf(if (self.inputs.isKeyDown(ScanCode.A)) 1 else 0));
        input = input.sub(left.mulf(if (self.inputs.isKeyDown(ScanCode.D)) 1 else 0));
        input = input.add(up.mulf(if (self.inputs.isKeyDown(ScanCode.E)) 1 else 0));
        input = input.sub(up.mulf(if (self.inputs.isKeyDown(ScanCode.Q)) 1 else 0));
    } else {
        self.inputs.setRelativeMouseMode(false);
    }

    // Normalize movement speed
    input = input.normalized().mulf(5);

    // Mouse wheel for zooming in and out relative to view direction
    const wheel = self.inputs.mouseWheel();
    const scroll_speed: f32 = if (self.inputs.isKeyDown(ScanCode.LeftCtrl)) 5 else 20;
    if (wheel.y > 0) {
        input = input.add(forward.mulf(scroll_speed));
    } else if (wheel.y < 0) {
        input = input.sub(forward.mulf(scroll_speed));
    }

    // Apply camera movements
    if (input.squaredLen() > (0.1 * 0.1)) {
        const camera_delta = input.mulf(ctx.delta);
        self.camera_pos = Vec3.add(self.camera_pos, camera_delta);
    }
    if (input_rot.squaredLen() > (0.1 * 0.1)) {
        const rot_delta = input_rot.mulf(ctx.delta * 1.0);
        self.camera_rot = self.camera_rot.add(rot_delta);
    }
}

pub fn draw(self: *Self, ctx: *GameApp) void {
    const cmd = ctx.engine.beginFrame();

    c.cImGui_ImplVulkan_NewFrame();
    c.cImGui_ImplSDL3_NewFrame();
    c.ImGui_NewFrame();
    if (self.imgui_demo_open) {
        c.ImGui_ShowDemoWindow(&self.imgui_demo_open);
    }

    if (c.ImGui_BeginMainMenuBar()) {
        if (c.ImGui_BeginMenu("File")) {
            if (c.ImGui_MenuItem("New")) {}
            if (c.ImGui_MenuItem("Open")) {}
            if (c.ImGui_MenuItem("Save")) {}
            if (c.ImGui_MenuItem("Quit")) {}
            c.ImGui_EndMenu();
        }
        if (c.ImGui_BeginMenu("Edit")) {
            if (c.ImGui_MenuItemEx("Undo", "CTRL+Z", false, true)) {}
            if (c.ImGui_MenuItemEx("Redo", "CTRL+Y", false, false)) {} // Disabled item
            c.ImGui_Separator();
            if (c.ImGui_MenuItemEx("Cut", "CTRL+X", false, true)) {}
            if (c.ImGui_MenuItemEx("Copy", "CTRL+C", false, true)) {}
            if (c.ImGui_MenuItemEx("Paste", "CTRL+V", false, true)) {}
            c.ImGui_EndMenu();
        }
        if (c.ImGui_BeginMenu("Help")) {
            _ = c.ImGui_MenuItemBoolPtr("ImGui Demo Window", null, &self.imgui_demo_open, true);
            c.ImGui_Separator();
            if (c.ImGui_MenuItem("About")) {}
            c.ImGui_EndMenu();
        }
        c.ImGui_SetCursorPosX((c.ImGui_GetCursorPosX() - (13 * 3)) + (GameApp.window_extent.width / 2) - c.ImGui_GetCursorPosX());
        if (c.ImGui_ImageButton("Play", if (self.play) self.stop_icon_ds else self.play_icon_ds, c.ImVec2{ .x = 13, .y = 13 })) {
            self.play = !self.play;
        }
        _ = c.ImGui_ImageButton("Pause", self.pause_icon_ds, c.ImVec2{ .x = 13, .y = 13 });
        _ = c.ImGui_ImageButton("Next", self.fast_forward_icon_ds, c.ImVec2{ .x = 13, .y = 13 });
        c.ImGui_EndMainMenuBar();
    }

    // We are using the ImGuiWindowFlags_NoDocking flag to make the parent window not dockable into,
    // because it would be confusing to have two docking targets within each others.
    var window_flags = c.ImGuiWindowFlags_MenuBar | c.ImGuiWindowFlags_NoDocking;

    const viewport = c.ImGui_GetMainViewport();
    c.ImGui_SetNextWindowPos(viewport.*.Pos, 0);
    c.ImGui_SetNextWindowSize(viewport.*.Size, 0);
    c.ImGui_SetNextWindowViewport(viewport.*.ID);
    c.ImGui_PushStyleVar(c.ImGuiStyleVar_WindowRounding, 0);
    c.ImGui_PushStyleVar(c.ImGuiStyleVar_WindowBorderSize, 0);
    window_flags |= c.ImGuiWindowFlags_NoTitleBar | c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoMove;
    window_flags |= c.ImGuiWindowFlags_NoBringToFrontOnFocus | c.ImGuiWindowFlags_NoNavFocus;

    // When using ImGuiDockNodeFlags_PassthruCentralNode, DockSpace() will render our background and handle the pass-thru hole, so we ask Begin() to not render a background.
    if ((self.dockspace_flags & c.ImGuiDockNodeFlags_PassthruCentralNode) > 0) {
        window_flags |= c.ImGuiWindowFlags_NoBackground;
    }

    // Important: note that we proceed even if Begin() returns false (aka window is collapsed).
    // This is because we want to keep our DockSpace() active. If a DockSpace() is inactive,
    // all active windows docked into it will lose their parent and become undocked.
    // We cannot preserve the docking relationship between an active window and an inactive docking, otherwise
    // any change of dockspace/settings would lead to windows being stuck in limbo and never being visible.
    c.ImGui_PushStyleVarImVec2(c.ImGuiStyleVar_WindowPadding, c.ImVec2{ .x = 0, .y = 0 });
    _ = c.ImGui_Begin("DockSpace", null, window_flags);
    c.ImGui_PopStyleVar();
    c.ImGui_PopStyleVarEx(2);

    // DockSpace
    const io = c.ImGui_GetIO();
    if ((io.*.ConfigFlags & c.ImGuiConfigFlags_DockingEnable) > 0) {
        var dockspace_id = c.ImGui_GetID("MyDockSpace");
        _ = c.ImGui_DockSpaceEx(dockspace_id, c.ImVec2{ .x = 0, .y = 0 }, self.dockspace_flags, null);

        if (self.first_time) {
            self.first_time = false;

            c.ImGui_DockBuilderRemoveNode(dockspace_id); // clear any previous layout
            _ = c.ImGui_DockBuilderAddNodeEx(dockspace_id, self.dockspace_flags | c.ImGuiDockNodeFlags_DockSpace);
            c.ImGui_DockBuilderSetNodeSize(dockspace_id, viewport.*.Size);

            // split the dockspace into 2 nodes -- DockBuilderSplitNode takes in the following args in the following order
            //   window ID to split, direction, fraction (between 0 and 1), the final two setting let's us choose which id we want (which ever one we DON'T set as NULL, will be returned by the function)
            //                                                              out_id_at_dir is the id of the node in the direction we specified earlier, out_id_at_opposite_dir is in the opposite direction
            const dock_id_left = c.ImGui_DockBuilderSplitNode(dockspace_id, c.ImGuiDir_Left, 0.2, null, &dockspace_id);
            const dock_id_down = c.ImGui_DockBuilderSplitNode(dockspace_id, c.ImGuiDir_Down, 0.25, null, &dockspace_id);

            // we now dock our windows into the docking node we made above
            c.ImGui_DockBuilderDockWindow("Assets", dock_id_down);
            c.ImGui_DockBuilderDockWindow("Hierarchy", dock_id_left);
            c.ImGui_DockBuilderFinish(dockspace_id);
        }
    }

    c.ImGui_End();

    _ = c.ImGui_Begin("Hierarchy", null, 0);
    for (ctx.engine.scene.root.children.items) |it| {
        drawHierarchyNode(it);
    }
    c.ImGui_End();

    _ = c.ImGui_Begin("Assets", null, 0);
    c.ImGui_Text("TODO");
    c.ImGui_End();

    _ = c.ImGui_Begin("Properties", null, 0);
    c.ImGui_Text("TODO");
    c.ImGui_End();

    _ = c.ImGui_Begin("Game", null, 0);
    self.is_game_window_focused = c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_None);
    const game_image = c.ImGui_GetWindowDrawList();
    self.game_view_size = c.ImGui_GetWindowSize();
    const FrameData = struct { app: *GameApp, cmd: GameApp.RenderCommand, d: *Self };
    var frame_userdata = FrameData{ .app = ctx, .cmd = cmd, .d = self };
    c.ImDrawList_AddCallback(game_image, extern struct {
        fn f(dl: [*c]const c.ImDrawList, dc: [*c]const c.ImDrawCmd) callconv(.C) void {
            _ = dl;
            const me: *FrameData = @alignCast(@ptrCast(dc.*.UserCallbackData));
            // const cmd = me.get_current_frame().main_command_buffer;
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
            me.app.engine.main_camera.updateMatrices(
                me.app.engine.camera_pos,
                Vec3.ZERO,
                aspect,
            );
            me.app.engine.drawObjects(
                me.cmd,
                me.app.engine.scene.renderables.items,
                me.app.engine.camera_and_scene_buffer,
                me.app.engine.camera_and_scene_set,
                &me.app.engine.main_camera,
            );

            c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                .offset = .{ .x = 0, .y = 0 },
                .extent = GameApp.window_extent,
            }});
        }
    }.f, &frame_userdata);
    c.ImDrawList_AddCallback(game_image, c.ImDrawCallback_ResetRenderState, null);
    c.ImGui_End();

    _ = c.ImGui_Begin("Scene", null, 0);
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
            me.app.engine.drawObjects(
                me.cmd,
                me.app.engine.scene.renderables.items,
                me.d.editor_camera_and_scene_buffer,
                me.d.editor_camera_and_scene_set,
                &me.d.camera,
            );

            c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                .offset = .{ .x = 0, .y = 0 },
                .extent = GameApp.window_extent,
            }});
        }
    }.f, &frame_userdata);
    c.ImDrawList_AddCallback(editor_image, c.ImDrawCallback_ResetRenderState, null);
    c.ImGui_Text("Camera Position: Vec3{ .x = %f, .y = %f, .z = %f }", self.camera_pos.x, self.camera_pos.y, self.camera_pos.z);
    c.ImGui_Text("Camera Rotation: Vec3{ .x = %f, .y = %f, .z = %f }", self.camera_rot.x, self.camera_rot.y, self.camera_rot.z);

    gizmo.newFrame(editor_image, self.camera.view, self.camera.view_projection, .{
        .x = self.scene_window_rect.x,
        .y = self.scene_window_rect.y,
        .width = self.scene_view_size.x,
        .height = self.scene_view_size.y,
    });

    if (ctx.engine.scene.renderables.items.len > 0) {
        const r = ctx.engine.scene.renderables.items[0];
        gizmo.drawBoundingBox(r.worldBounds()) catch @panic("error");
        const components = r.object.transform.decomposeComponents();
        gizmo.manipulate(
            components.translation,
            Vec3.ZERO,
            components.scale,
        ) catch @panic("error");
    }
    gizmo.endFrame();
    c.ImGui_End();

    c.ImGui_Render();

    // UI
    c.cImGui_ImplVulkan_RenderDrawData(c.ImGui_GetDrawData(), cmd);

    ctx.engine.beginPresentRenderPass(cmd);

    ctx.engine.endFrame(cmd);
}

fn init_descriptors(self: *Self, engine: *Engine) void {
    const camera_and_scene_buffer_size =
        FRAME_OVERLAP * engine.padUniformBufferSize(@sizeOf(GPUCameraData)) +
        FRAME_OVERLAP * engine.padUniformBufferSize(@sizeOf(GPUSceneData));
    self.editor_camera_and_scene_buffer = engine.createBuffer(
        camera_and_scene_buffer_size,
        c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    engine.buffer_deletion_queue.append(VmaBufferDeleter{ .buffer = self.editor_camera_and_scene_buffer }) catch @panic("Out of memory");

    // Camera and scene descriptor set
    const global_set_alloc_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = engine.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &engine.global_set_layout,
    });

    // Allocate a single set for multiple frame worth of camera and scene data
    check_vk(c.vkAllocateDescriptorSets(engine.device, &global_set_alloc_info, &self.editor_camera_and_scene_set)) catch @panic("Failed to allocate global descriptor set");

    // editor Camera
    const editor_camera_buffer_info = std.mem.zeroInit(c.VkDescriptorBufferInfo, .{
        .buffer = self.editor_camera_and_scene_buffer.buffer,
        .range = @sizeOf(GPUCameraData),
    });

    const editor_camera_write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = self.editor_camera_and_scene_set,
        .dstBinding = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
        .pBufferInfo = &editor_camera_buffer_info,
    });

    // editor Scene parameters
    const editor_scene_parameters_buffer_info = std.mem.zeroInit(c.VkDescriptorBufferInfo, .{
        .buffer = self.editor_camera_and_scene_buffer.buffer,
        .range = @sizeOf(GPUSceneData),
    });

    const editor_scene_parameters_write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = self.editor_camera_and_scene_set,
        .dstBinding = 1,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
        .pBufferInfo = &editor_scene_parameters_buffer_info,
    });

    const editor_camera_and_scene_writes = [_]c.VkWriteDescriptorSet{
        editor_camera_write,
        editor_scene_parameters_write,
    };

    c.vkUpdateDescriptorSets(engine.device, @as(u32, @intCast(editor_camera_and_scene_writes.len)), &editor_camera_and_scene_writes[0], 0, null);
}

fn init_imgui(self: *Self, engine: *Engine) void {
    const pool_sizes = [_]c.VkDescriptorPoolSize{
        .{
            .type = c.VK_DESCRIPTOR_TYPE_SAMPLER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC,
            .descriptorCount = 1000,
        },
        .{
            .type = c.VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT,
            .descriptorCount = 1000,
        },
    };

    const pool_ci = std.mem.zeroInit(c.VkDescriptorPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        .maxSets = 1000,
        .poolSizeCount = @as(u32, @intCast(pool_sizes.len)),
        .pPoolSizes = &pool_sizes[0],
    });

    var imgui_pool: c.VkDescriptorPool = undefined;
    check_vk(c.vkCreateDescriptorPool(engine.device, &pool_ci, Engine.vk_alloc_cbs, &imgui_pool)) catch @panic("Failed to create imgui descriptor pool");

    _ = c.ImGui_CreateContext(null);
    _ = c.cImGui_ImplSDL3_InitForVulkan(engine.window);

    var init_info = std.mem.zeroInit(c.ImGui_ImplVulkan_InitInfo, .{
        .Instance = engine.instance,
        .PhysicalDevice = engine.physical_device,
        .Device = engine.device,
        .QueueFamily = engine.graphics_queue_family,
        .Queue = engine.graphics_queue,
        .DescriptorPool = imgui_pool,
        .MinImageCount = FRAME_OVERLAP,
        .ImageCount = FRAME_OVERLAP,
        .MSAASamples = c.VK_SAMPLE_COUNT_1_BIT,
    });

    const io = c.ImGui_GetIO();
    _ = c.ImFontAtlas_AddFontFromFileTTF(io.*.Fonts, "assets/editor/fonts/roboto.ttf", 14, null, null);

    _ = c.cImGui_ImplVulkan_Init(&init_info, engine.render_pass);
    _ = c.cImGui_ImplVulkan_CreateFontsTexture();

    self.play_icon_ds = create_imgui_texture("assets/editor/icons/play.png", engine);
    self.pause_icon_ds = create_imgui_texture("assets/editor/icons/pause.png", engine);
    self.stop_icon_ds = create_imgui_texture("assets/editor/icons/stop.png", engine);
    self.fast_forward_icon_ds = create_imgui_texture("assets/editor/icons/fast-forward.png", engine);

    engine.deletion_queue.append(VulkanDeleter.make(imgui_pool, c.vkDestroyDescriptorPool)) catch @panic("Out of memory");

    io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    io.*.ConfigWindowsMoveFromTitleBarOnly = true;

    // set visual studio theme
    const style = c.ImGui_GetStyle();
    style.*.Alpha = 1.0;
    style.*.DisabledAlpha = 0.6000000238418579;
    style.*.WindowPadding = c.ImVec2{ .x = 8.0, .y = 8.0 };
    style.*.WindowRounding = 0.0;
    style.*.WindowBorderSize = 1.0;
    style.*.WindowMinSize = c.ImVec2{ .x = 32.0, .y = 32.0 };
    style.*.WindowTitleAlign = c.ImVec2{ .x = 0.0, .y = 0.5 };
    style.*.WindowMenuButtonPosition = c.ImGuiDir_Left;
    style.*.ChildRounding = 0.0;
    style.*.ChildBorderSize = 1.0;
    style.*.PopupRounding = 0.0;
    style.*.PopupBorderSize = 1.0;
    style.*.FramePadding = c.ImVec2{ .x = 4.0, .y = 3.0 };
    style.*.FrameRounding = 0.0;
    style.*.FrameBorderSize = 0.0;
    style.*.ItemSpacing = c.ImVec2{ .x = 8.0, .y = 4.0 };
    style.*.ItemInnerSpacing = c.ImVec2{ .x = 4.0, .y = 4.0 };
    style.*.CellPadding = c.ImVec2{ .x = 4.0, .y = 2.0 };
    style.*.IndentSpacing = 21.0;
    style.*.ColumnsMinSpacing = 6.0;
    style.*.ScrollbarSize = 14.0;
    style.*.ScrollbarRounding = 0.0;
    style.*.GrabMinSize = 10.0;
    style.*.GrabRounding = 0.0;
    style.*.TabRounding = 0.0;
    style.*.TabBorderSize = 0.0;
    style.*.TabMinWidthForCloseButton = 0.0;
    style.*.ColorButtonPosition = c.ImGuiDir_Right;
    style.*.ButtonTextAlign = c.ImVec2{ .x = 0.5, .y = 0.5 };
    style.*.SelectableTextAlign = c.ImVec2{ .x = 0.0, .y = 0.0 };

    style.*.Colors[c.ImGuiCol_Text] = c.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TextDisabled] = c.ImVec4{ .x = 0.5921568870544434, .y = 0.5921568870544434, .z = 0.5921568870544434, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_WindowBg] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ChildBg] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PopupBg] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_Border] = c.ImVec4{ .x = 0.3058823645114899, .y = 0.3058823645114899, .z = 0.3058823645114899, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_BorderShadow] = c.ImVec4{ .x = 0.3058823645114899, .y = 0.3058823645114899, .z = 0.3058823645114899, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_FrameBg] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_FrameBgHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_FrameBgActive] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TitleBg] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TitleBgActive] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TitleBgCollapsed] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_MenuBarBg] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarBg] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarGrab] = c.ImVec4{ .x = 0.321568638086319, .y = 0.321568638086319, .z = 0.3333333432674408, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarGrabHovered] = c.ImVec4{ .x = 0.3529411852359772, .y = 0.3529411852359772, .z = 0.3725490272045135, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarGrabActive] = c.ImVec4{ .x = 0.3529411852359772, .y = 0.3529411852359772, .z = 0.3725490272045135, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_CheckMark] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_SliderGrab] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_SliderGrabActive] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_Button] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ButtonHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ButtonActive] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_Header] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_HeaderHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_HeaderActive] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_Separator] = c.ImVec4{ .x = 0.3058823645114899, .y = 0.3058823645114899, .z = 0.3058823645114899, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_SeparatorHovered] = c.ImVec4{ .x = 0.3058823645114899, .y = 0.3058823645114899, .z = 0.3058823645114899, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_SeparatorActive] = c.ImVec4{ .x = 0.3058823645114899, .y = 0.3058823645114899, .z = 0.3058823645114899, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ResizeGrip] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ResizeGripHovered] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ResizeGripActive] = c.ImVec4{ .x = 0.321568638086319, .y = 0.321568638086319, .z = 0.3333333432674408, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_Tab] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabActive] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabUnfocused] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabUnfocusedActive] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotLines] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotLinesHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotHistogram] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotHistogramHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableHeaderBg] = c.ImVec4{ .x = 0.1882352977991104, .y = 0.1882352977991104, .z = 0.2000000029802322, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableBorderStrong] = c.ImVec4{ .x = 0.3098039329051971, .y = 0.3098039329051971, .z = 0.3490196168422699, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableBorderLight] = c.ImVec4{ .x = 0.2274509817361832, .y = 0.2274509817361832, .z = 0.2470588237047195, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableRowBg] = c.ImVec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 };
    style.*.Colors[c.ImGuiCol_TableRowBgAlt] = c.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 0.05999999865889549 };
    style.*.Colors[c.ImGuiCol_TextSelectedBg] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_DragDropTarget] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_NavHighlight] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_NavWindowingHighlight] = c.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 0.699999988079071 };
    style.*.Colors[c.ImGuiCol_NavWindowingDimBg] = c.ImVec4{ .x = 0.800000011920929, .y = 0.800000011920929, .z = 0.800000011920929, .w = 0.2000000029802322 };
    style.*.Colors[c.ImGuiCol_ModalWindowDimBg] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
}

fn drawHierarchyNode(obj: *Object) void {
    var node_flags = c.ImGuiTreeNodeFlags_OpenOnArrow;
    if (obj.children.items.len == 0) {
        node_flags = c.ImGuiTreeNodeFlags_Leaf;
    }
    if (c.ImGui_TreeNodeEx(obj.name.ptr, node_flags)) {
        for (obj.children.items) |it| {
            drawHierarchyNode(it);
        }
        c.ImGui_TreePop();
    }
}

fn create_imgui_texture(filepath: []const u8, engine: *Engine) c.VkDescriptorSet {
    const img = textures.load_image_from_file(engine, filepath) catch @panic("Failed to load image");
    engine.image_deletion_queue.append(VmaImageDeleter{ .image = img }) catch @panic("Out of memory");

    // Create the Image View
    var image_view: c.VkImageView = undefined;
    {
        const info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = img.image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = c.VK_FORMAT_R8G8B8A8_UNORM,
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .levelCount = 1,
                .layerCount = 1,
            },
        };
        check_vk(c.vkCreateImageView(engine.device, &info, Engine.vk_alloc_cbs, &image_view)) catch @panic("Failed to create image view");
    }
    engine.textures.put(filepath, Texture{ .image = img, .image_view = image_view }) catch @panic("OOM");
    engine.deletion_queue.append(VulkanDeleter.make(image_view, c.vkDestroyImageView)) catch @panic("OOM");
    // Create Sampler
    var sampler: c.VkSampler = undefined;
    {
        const sampler_info = c.VkSamplerCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = c.VK_FILTER_LINEAR,
            .minFilter = c.VK_FILTER_LINEAR,
            .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
            .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT, // outside image bounds just use border color
            .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .minLod = -1000,
            .maxLod = 1000,
            .maxAnisotropy = 1.0,
        };
        check_vk(c.vkCreateSampler(engine.device, &sampler_info, Engine.vk_alloc_cbs, &sampler)) catch @panic("Failed to create sampler");
    }
    engine.deletion_queue.append(VulkanDeleter.make(sampler, c.vkDestroySampler)) catch @panic("OOM");
    return c.cImGui_ImplVulkan_AddTexture(sampler, image_view, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
}
