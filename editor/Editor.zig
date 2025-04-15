const c = @import("clibs");

const std = @import("std");

const gizmo = @import("gizmo.zig");

const check_vk = @import("yume").vki.check_vk;

const Uuid = @import("yume").Uuid;
const EditorDatabase = @import("EditorDatabase.zig");
const Editors = @import("editors/editors.zig");
const Project = @import("Project.zig");
const AssetsDatabase = @import("yume").AssetsDatabase;

const HierarchyWindow = @import("windows/HierarchyWindow.zig");
const ProjectExplorerWindow = @import("windows/ProjectExplorerWindow.zig");
const PropertiesWindow = @import("windows/PropertiesWindow.zig");
const SceneWindow = @import("windows/SceneWindow.zig");
const GameWindow = @import("windows/GameWindow.zig");

const imutils = @import("imutils.zig");

const textures = @import("yume").textures;
const Texture = textures.Texture;

const Camera = @import("yume").Camera;
const Scene = @import("yume").scene_graph.Scene;
const Object = @import("yume").scene_graph.Object;
const MeshRenderer = @import("yume").MeshRenderer;
const ScanCode = @import("yume").inputs.ScanCode;
const MouseButton = @import("yume").inputs.MouseButton;
const InputsContext = @import("yume").inputs.InputContext;

const ecs = @import("yume").ecs;
const systems = @import("yume").systems;
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

const NewProjectModal = @import("NewProjectModal.zig");
const OpenProjectModal = @import("OpenProjectModal.zig");
const HelloModal = @import("HelloModal.zig");

const ManipulationTool = enum {
    move,
    rotate,
    scale,
};

const SelectionKind = enum { none, entity, many };
const Selection = union(SelectionKind) {
    none: void,
    entity: ecs.Entity,
    many: []Selection,

    pub fn is(self: *const Selection, comptime kind: SelectionKind, other: anytype) bool {
        if (kind != std.meta.activeTag(self.*)) {
            return false;
        }

        switch (self.*) {
            .none => return true,
            .entity => |e| return e == other,
            .many => return false,
        }
    }

    pub fn contains(self: *const Selection, comptime kind: SelectionKind, other: anytype) bool {
        switch (self.*) {
            .none, .entity => return self.is(kind, other),
            .many => |ms| return ms.len > 0 and blk: {
                for (ms) |m| {
                    if (m.is(kind, other)) {
                        break :blk true;
                    }
                }
                break :blk false;
            },
        }
    }
};

const Self = @This();

selection: Selection = .none,

play: bool = false,
imgui_demo_open: bool = false,

dockspace_flags: c.ImGuiDockNodeFlags = 0,

editors: Editors,

first_time: bool = true,

hello_modal: HelloModal,
new_project_modal: NewProjectModal,
open_project_modal: OpenProjectModal,

hierarchy_window: HierarchyWindow,
project_explorer: ProjectExplorerWindow,
properties_window: PropertiesWindow,
scene_window: SceneWindow,
game_window: GameWindow,

pub fn init(ctx: *GameApp) *Self {
    ctx.world.tag(RunInEditor);
    ctx.world.tag(Playing);
    ctx.world.addSingleton(Playing);
    ctx.world.enable(ecs.typeId(Playing), false);
    const tmu_entity = ctx.world.systemFn("transform-matrix-update", ecs.systems.PostUpdate, systems.transformMatrices);
    ctx.world.add(tmu_entity, RunInEditor);

    const home_dir = std.fs.selfExeDirPathAlloc(ctx.allocator) catch @panic("OOM");
    defer ctx.allocator.free(home_dir);
    const db_path = std.fs.path.join(ctx.allocator, &[_][]const u8{ home_dir, ".user-data", "db.json" }) catch @panic("OOM");
    defer ctx.allocator.free(db_path);

    EditorDatabase.init(ctx.allocator, db_path) catch @panic("Faield to load editor database");
    inputs = InputsContext{ .window = ctx.window };
    singleton = Self{
        .editors = Editors.init(ctx.allocator),
        .hello_modal = HelloModal.init() catch @panic("Failed to initialize `HelloModal`"),
        .new_project_modal = NewProjectModal.init(ctx.allocator) catch @panic("Failed to initialize `NewProjectModal`"),
        .open_project_modal = OpenProjectModal.init(ctx.allocator) catch @panic("Failed to initialize `OpenProjectModal`"),
        .hierarchy_window = HierarchyWindow.init(ctx),
        .project_explorer = ProjectExplorerWindow{},
        .properties_window = PropertiesWindow{},
        .scene_window = SceneWindow.init(ctx),
        .game_window = GameWindow{},
    };
    singleton.bootstrapEditorPipeline(ctx.world);
    singleton.init_descriptors(&ctx.engine);
    init_imgui(&ctx.engine);

    if (EditorDatabase.storage().last_open_project) |lop| {
        Project.load(ctx.allocator, lop) catch {
            std.debug.print("Failed to load previously loaded project {s}", .{lop});
        };

        if (EditorDatabase.storage().last_open_scene) |los| {
            ctx.loadScene(los) catch {
                std.debug.print("Failed to load previously loaded project {s}", .{lop});
            };
        }
    }

    render_system = ctx.world.systemEx(.{
        .entity = ctx.world.create("Render"),
        .query = std.mem.zeroInit(c.ecs_query_desc_t, .{ .terms = .{
            .{ .id = c.EcsAny },
        } }),
        .callback = &struct {
            fn f(_: [*c]ecs.Iter) callconv(.C) void {
                // std.debug.print("HERE \n", .{});
            }
        }.f,
    });

    return &singleton;
}

pub fn deinit(self: *Self, ctx: *GameApp) void {
    self.editors.deinit();
    self.hello_modal.deinit();
    self.new_project_modal.deinit();
    self.open_project_modal.deinit();
    self.hierarchy_window.deinit();
    if (Project.current()) |p| {
        p.unload();
    }
    check_vk(c.vkDeviceWaitIdle(ctx.engine.device)) catch @panic("Failed to wait for device idle");
    c.cImGui_ImplVulkan_Shutdown();
    EditorDatabase.flush() catch std.debug.print("Failed to flush the editor database", .{});
    EditorDatabase.deinit();
}

pub fn newFrame(_: *Self, _: *GameApp) void {
    inputs.clear();
}

pub fn processEvent(self: *Self, ctx: *GameApp, event: *c.SDL_Event) bool {
    _ = c.cImGui_ImplSDL3_ProcessEvent(event);
    switch (event.type) {
        c.SDL_EVENT_KEY_UP => {
            if (event.key.scancode == c.SDL_SCANCODE_ESCAPE) {
                c.ImGui_FocusWindow(null, c.ImGuiFocusRequestFlags_None);
            }
        },
        c.SDL_EVENT_QUIT => return false,
        else => {},
    }
    if (self.game_window.is_game_window_focused) {
        ctx.inputs.push(event);
    } else if (self.scene_window.is_scene_window_focused) {
        inputs.push(event);
    }

    return true;
}

fn isInGameView(self: *Self, pos: c.ImVec2) bool {
    return (pos.x > self.game_window.game_window_rect.x and pos.x < self.game_window.game_window_rect.z) and
        (pos.y > self.game_window.game_window_rect.y and pos.y < self.game_window.game_window_rect.w);
}

fn isInSceneView(self: *Self, pos: c.ImVec2) bool {
    return (pos.x > self.scene_window_rect.x and pos.x < self.scene_window_rect.z) and
        (pos.y > self.scene_window_rect.y and pos.y < self.scene_window_rect.w);
}

pub fn update(self: *Self, ctx: *GameApp) bool {
    var input: Vec3 = Vec3.make(0, 0, 0);
    var input_rot: Vec3 = Vec3.make(0, 0, 0);

    // Create rotation quaternion
    const rot_x = Quat.fromAxisAngle(Vec3.make(1.0, 0.0, 0.0), self.scene_window.camera_rot.x);
    const rot_y = Quat.fromAxisAngle(Vec3.make(0.0, 1.0, 0.0), self.scene_window.camera_rot.y);
    const rot_z = Quat.fromAxisAngle(Vec3.make(0.0, 0.0, 1.0), self.scene_window.camera_rot.z);
    const rot_quat = rot_z.mul(rot_y).mul(rot_x);

    // Calculate direction vectors
    const forward = rot_quat.mulVec3(Vec3.make(0, 0, 1)).normalized();
    const left = rot_quat.mulVec3(Vec3.make(-1, 0, 0)).normalized();
    const up = Vec3.cross(left, forward).normalized();

    if (inputs.isMouseButtonDown(MouseButton.Middle)) {
        inputs.setRelativeMouseMode(true);
        // Shift + MMB for panning
        if (inputs.isKeyDown(ScanCode.LeftShift)) {
            const mouse_delta = inputs.mouseDelta();
            input = input.add(left.mulf(mouse_delta.x));
            input = input.add(up.mulf(mouse_delta.y));
        } else { // Camera rotation handling (MMB for orbiting)
            const mouse_delta = inputs.mouseRelative();
            input_rot.y += mouse_delta.x;
            input_rot.x += mouse_delta.y;
        }
        // Handle translation inputs (W, A, S, D for panning) relative to view
        input = input.add(forward.mulf(if (inputs.isKeyDown(ScanCode.W)) 1 else 0));
        input = input.sub(forward.mulf(if (inputs.isKeyDown(ScanCode.S)) 1 else 0));
        input = input.add(left.mulf(if (inputs.isKeyDown(ScanCode.A)) 1 else 0));
        input = input.sub(left.mulf(if (inputs.isKeyDown(ScanCode.D)) 1 else 0));
        input = input.add(up.mulf(if (inputs.isKeyDown(ScanCode.E)) 1 else 0));
        input = input.sub(up.mulf(if (inputs.isKeyDown(ScanCode.Q)) 1 else 0));
    } else {
        inputs.setRelativeMouseMode(false);
    }

    // Normalize movement speed
    input = input.normalized().mulf(5);

    if (inputs.isKeyDown(ScanCode.LeftCtrl)) {
        // Mouse wheel for zooming in and out relative to view direction
        const wheel = inputs.mouseWheel();
        const scroll_speed: f32 = if (inputs.isKeyDown(ScanCode.LeftShift)) 5 else 20;
        if (wheel.y > 0) {
            input = input.add(forward.mulf(scroll_speed));
        } else if (wheel.y < 0) {
            input = input.sub(forward.mulf(scroll_speed));
        }
    }

    // Apply camera movements
    if (input.squaredLen() > (0.1 * 0.1)) {
        const camera_delta = input.mulf(ctx.delta);
        self.scene_window.camera_pos = Vec3.add(self.scene_window.camera_pos, camera_delta);
    }
    if (input_rot.squaredLen() > (0.1 * 0.1)) {
        const rot_delta = input_rot.mulf(ctx.delta * 1.0);
        self.scene_window.camera_rot = self.scene_window.camera_rot.add(rot_delta);
    }

    return ctx.world.progress(ctx.delta);
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
        if (c.ImGui_BeginMenu("Project")) {
            if (c.ImGui_MenuItem("New")) {
                self.new_project_modal.open();
            }
            if (c.ImGui_MenuItem("Open")) {
                self.open_project_modal.open();
            }
            if (c.ImGui_MenuItem("Save*")) {}
            if (c.ImGui_MenuItem("Quit*")) {}
            c.ImGui_EndMenu();
        }
        if (c.ImGui_BeginMenu("Scene")) {
            if (c.ImGui_MenuItem("New*")) {}
            if (c.ImGui_MenuItem("Load*")) {}
            if (c.ImGui_MenuItemEx("Save", "CTRL+S", false, true)) {
                if (ctx.scene_handle) |hndl| {
                    const path = Project.getResourcePath(hndl.uuid) catch @panic("Scene not found!");
                    const json = std.json.stringifyAlloc(ctx.allocator, ctx.scene, .{ .whitespace = .indent_4 }) catch @panic("Failed to serialize the scene");
                    defer ctx.allocator.free(json);
                    var file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch @panic("Failed to open scene file to save");
                    defer file.close();
                    file.setEndPos(0) catch @panic("Failed to truncate the scene file");
                    file.seekTo(0) catch @panic("Failed to seek the start of the scene file");
                    file.writeAll(json) catch @panic("Failed to write scene data");
                } else {
                    std.debug.print("Saving new scene not implemented yet\n", .{}); // TODO
                }
            }
            c.ImGui_EndMenu();
        }
        if (c.ImGui_BeginMenu("Edit")) {
            if (c.ImGui_MenuItemEx("Undo*", "CTRL+Z", false, true)) {}
            if (c.ImGui_MenuItemEx("Redo*", "CTRL+Y", false, false)) {} // Disabled item
            c.ImGui_Separator();
            if (c.ImGui_MenuItemEx("Cut*", "CTRL+X", false, true)) {}
            if (c.ImGui_MenuItemEx("Copy*", "CTRL+C", false, true)) {}
            if (c.ImGui_MenuItemEx("Paste*", "CTRL+V", false, true)) {}
            c.ImGui_EndMenu();
        }
        if (c.ImGui_BeginMenu("Help")) {
            _ = c.ImGui_MenuItemBoolPtr("ImGui Demo Window", null, &self.imgui_demo_open, true);
            c.ImGui_Separator();
            if (c.ImGui_MenuItem("About*")) {}
            c.ImGui_EndMenu();
        }
        c.ImGui_SetCursorPosX((c.ImGui_GetCursorPosX() - (13 * 3)) + (GameApp.window_extent.width / 2) - c.ImGui_GetCursorPosX());
        if (c.ImGui_ImageButton("Play", @intFromPtr(if (self.play) stop_icon_ds else play_icon_ds), c.ImVec2{ .x = 13, .y = 13 })) {
            self.play = !self.play;
            ctx.world.enable(ecs.typeId(Playing), self.play);
            self.bootstrapEditorPipeline(ctx.world);
        }
        _ = c.ImGui_ImageButton("Pause", @intFromPtr(pause_icon_ds), c.ImVec2{ .x = 13, .y = 13 });
        _ = c.ImGui_ImageButton("Next", @intFromPtr(fast_forward_icon_ds), c.ImVec2{ .x = 13, .y = 13 });
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
            const dock_id_right = c.ImGui_DockBuilderSplitNode(dockspace_id, c.ImGuiDir_Right, 0.2, null, &dockspace_id);
            const dock_id_down = c.ImGui_DockBuilderSplitNode(dockspace_id, c.ImGuiDir_Down, 0.25, null, &dockspace_id);

            // we now dock our windows into the docking node we made above
            c.ImGui_DockBuilderDockWindow("Project", dock_id_down);
            c.ImGui_DockBuilderDockWindow("Hierarchy", dock_id_left);
            c.ImGui_DockBuilderDockWindow("Properties", dock_id_right);
            c.ImGui_DockBuilderDockWindow("Game", dockspace_id);
            c.ImGui_DockBuilderDockWindow("Scene", dockspace_id);
            c.ImGui_DockBuilderFinish(dockspace_id);
        }
    }

    c.ImGui_End();

    self.hierarchy_window.draw(ctx);
    self.properties_window.draw(ctx) catch @panic("err");
    self.project_explorer.draw();
    self.scene_window.draw(cmd, ctx);
    self.game_window.draw(cmd, ctx);

    self.hello_modal.show();
    self.new_project_modal.show(ctx);
    self.open_project_modal.show(ctx);

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
    self.scene_window.editor_camera_and_scene_buffer = engine.createBuffer(
        camera_and_scene_buffer_size,
        c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    engine.buffer_deletion_queue.append(VmaBufferDeleter{ .buffer = self.scene_window.editor_camera_and_scene_buffer }) catch @panic("Out of memory");

    // Camera and scene descriptor set
    const global_set_alloc_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = engine.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &engine.global_set_layout,
    });

    // Allocate a single set for multiple frame worth of camera and scene data
    check_vk(c.vkAllocateDescriptorSets(engine.device, &global_set_alloc_info, &self.scene_window.editor_camera_and_scene_set)) catch @panic("Failed to allocate global descriptor set");

    // editor Camera
    const editor_camera_buffer_info = std.mem.zeroInit(c.VkDescriptorBufferInfo, .{
        .buffer = self.scene_window.editor_camera_and_scene_buffer.buffer,
        .range = @sizeOf(GPUCameraData),
    });

    const editor_camera_write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = self.scene_window.editor_camera_and_scene_set,
        .dstBinding = 0,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
        .pBufferInfo = &editor_camera_buffer_info,
    });

    // editor Scene parameters
    const editor_scene_parameters_buffer_info = std.mem.zeroInit(c.VkDescriptorBufferInfo, .{
        .buffer = self.scene_window.editor_camera_and_scene_buffer.buffer,
        .range = @sizeOf(GPUSceneData),
    });

    const editor_scene_parameters_write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = self.scene_window.editor_camera_and_scene_set,
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

fn init_imgui(engine: *Engine) void {
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
        .RenderPass = engine.render_pass,
        .QueueFamily = engine.graphics_queue_family,
        .Queue = engine.graphics_queue,
        .DescriptorPool = imgui_pool,
        .MinImageCount = FRAME_OVERLAP,
        .ImageCount = FRAME_OVERLAP,
        .MSAASamples = c.VK_SAMPLE_COUNT_1_BIT,
    });

    const io = c.ImGui_GetIO();
    roboto14 = c.ImFontAtlas_AddFontFromFileTTF(io.*.Fonts, "assets/editor/fonts/roboto.ttf", 14, null, null);
    roboto24 = c.ImFontAtlas_AddFontFromFileTTF(io.*.Fonts, "assets/editor/fonts/roboto.ttf", 24, null, null);
    roboto32 = c.ImFontAtlas_AddFontFromFileTTF(io.*.Fonts, "assets/editor/fonts/roboto.ttf", 32, null, null);

    _ = c.cImGui_ImplVulkan_Init(&init_info);
    _ = c.cImGui_ImplVulkan_CreateFontsTexture();

    play_icon_ds = create_imgui_texture("assets/editor/icons/play.png", engine);
    pause_icon_ds = create_imgui_texture("assets/editor/icons/pause.png", engine);
    stop_icon_ds = create_imgui_texture("assets/editor/icons/stop.png", engine);
    fast_forward_icon_ds = create_imgui_texture("assets/editor/icons/fast-forward.png", engine);
    folder_icon_ds = create_imgui_texture("assets/editor/icons/folder.png", engine);
    file_icon_ds = create_imgui_texture("assets/editor/icons/file.png", engine);
    object_icon_ds = create_imgui_texture("assets/editor/icons/object.png", engine);
    move_tool_icon_ds = create_imgui_texture("assets/editor/icons/move-tool.png", engine);
    rotate_tool_icon_ds = create_imgui_texture("assets/editor/icons/rotate-tool.png", engine);
    scale_tool_icon_ds = create_imgui_texture("assets/editor/icons/scale-tool.png", engine);
    close_icon_ds = create_imgui_texture("assets/editor/icons/close.png", engine);
    browse_icon_ds = create_imgui_texture("assets/editor/icons/browse.png", engine);

    yume_logo_ds = create_imgui_texture("assets/editor/icons/yume.png", engine);

    engine.deletion_queue.append(VulkanDeleter.make(imgui_pool, c.vkDestroyDescriptorPool)) catch @panic("Out of memory");

    io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    io.*.ConfigWindowsMoveFromTitleBarOnly = true;

    loadImGuiTheme();
}

pub fn instance() *Self {
    return &singleton;
}

pub fn newProject(self: *Self) void {
    self.new_project_modal.open();
}

pub fn openProject(self: *Self) void {
    self.open_project_modal.open();
}

fn create_imgui_texture(filepath: []const u8, engine: *Engine) c.VkDescriptorSet {
    var file = std.fs.cwd().openFile(filepath, .{}) catch @panic("Failed to open the file");
    defer file.close();
    const content = file.readToEndAlloc(engine.allocator, 30_000_000) catch @panic("OOM");
    defer engine.allocator.free(content);
    const img = textures.load_image(engine, content, Uuid.new().urn()) catch @panic("Failed to load image");
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

fn bootstrapEditorPipeline(self: *const Self, world: ecs.World) void {
    var query = c.ecs_query_desc_t{};
    query.terms[0] = .{ .id = ecs.core.System };
    query.terms[1] = .{ .id = ecs.systems.Phase, .src = .{ .id = c.EcsCascade }, .trav = ecs.relations.DependsOn };
    query.terms[2] = .{ .id = c.ecs_dependson(ecs.systems.OnStart), .trav = ecs.relations.DependsOn, .oper = c.EcsNot };
    query.terms[3] = .{ .id = c.EcsDisabled, .src = .{ .id = c.EcsUp }, .trav = ecs.relations.DependsOn, .oper = c.EcsNot };
    query.terms[4] = .{ .id = c.EcsDisabled, .src = .{ .id = c.EcsUp }, .trav = ecs.relations.ChildOf, .oper = c.EcsNot };
    if (!self.play) {
        query.terms[5] = .{ .id = ecs.typeId(RunInEditor), .src = .{ .id = c.EcsThis } };
    }
    query.order_by_callback = flecs_entity_compare;
    query.cache_kind = c.EcsQueryCacheAuto;

    const old_pipeline = c.ecs_get_pipeline(world.inner);
    world.delete(old_pipeline);

    const pipeline = c.ecs_pipeline_init(world.inner, &.{
        .entity = world.createEx(&.{ .name = "EditorPipeline" }),
        .query = query,
    });
    c.ecs_set_pipeline(world.inner, pipeline);
}

const RunInEditor = extern struct {};
const Playing = extern struct {};

fn flecs_bootstrap_phase_(world: ecs.World, phase: ecs.Entity, depends_on: ecs.Entity) void {
    c.ecs_add_id(world.inner, phase, ecs.systems.Phase);
    world.addPair(phase, ecs.relations.DependsOn, depends_on);
}

fn flecs_entity_compare(e1: c.ecs_entity_t, _: ?*const anyopaque, e2: c.ecs_entity_t, _: ?*const anyopaque) callconv(.C) c_int {
    return @as(c_int, @intCast(@intFromBool((e1 > e2)))) - @intFromBool((e1 < e2));
}

fn loadImGuiTheme() void {
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

var singleton: Self = undefined;

pub var render_system: ecs.Entity = undefined;

pub var inputs: InputsContext = undefined;

pub var roboto14: *c.ImFont = undefined;
pub var roboto24: *c.ImFont = undefined;
pub var roboto32: *c.ImFont = undefined;

// assets

pub var play_icon_ds: c.VkDescriptorSet = undefined;
pub var pause_icon_ds: c.VkDescriptorSet = undefined;
pub var stop_icon_ds: c.VkDescriptorSet = undefined;
pub var fast_forward_icon_ds: c.VkDescriptorSet = undefined;
pub var folder_icon_ds: c.VkDescriptorSet = undefined;
pub var file_icon_ds: c.VkDescriptorSet = undefined;
pub var object_icon_ds: c.VkDescriptorSet = undefined;
pub var move_tool_icon_ds: c.VkDescriptorSet = undefined;
pub var rotate_tool_icon_ds: c.VkDescriptorSet = undefined;
pub var scale_tool_icon_ds: c.VkDescriptorSet = undefined;
pub var close_icon_ds: c.VkDescriptorSet = undefined;
pub var browse_icon_ds: c.VkDescriptorSet = undefined;

pub var yume_logo_ds: c.VkDescriptorSet = undefined;
