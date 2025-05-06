const c = @import("clibs");

const std = @import("std");
const log = std.log.scoped(.Editor);

const gizmo = @import("gizmo.zig");

const check_vk = @import("yume").vki.check_vk;

const Uuid = @import("yume").Uuid;
const EditorDatabase = @import("EditorDatabase.zig");
const Editors = @import("editors/editors.zig");
const Resources = @import("Resources.zig");
const Project = @import("Project.zig");
const Assets = @import("yume").Assets;

const HierarchyWindow = @import("windows/HierarchyWindow.zig");
const ResourcesWindow = @import("windows/ResourcesWindow.zig");
const PropertiesWindow = @import("windows/PropertiesWindow.zig");
const SceneWindow = @import("windows/SceneWindow.zig");
const GameWindow = @import("windows/GameWindow.zig");
const LogsWindow = @import("windows/LogsWindow.zig");

const imutils = @import("imutils.zig");

const textures = @import("yume").textures;
const Texture = textures.Texture;

const Camera = @import("yume").Camera;
const Scene = @import("yume").scene_graph.Scene;
const MeshRenderer = @import("yume").MeshRenderer;
const InputsContext = @import("yume").inputs.InputContext;

const ecs = @import("yume").ecs;
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

const styles = @import("styles.zig");

const ManipulationTool = enum {
    move,
    rotate,
    scale,
};

const SelectionKind = enum { none, entity, resource, many };
const Selection = union(SelectionKind) {
    none,
    entity: ecs.Entity,
    resource: Uuid,
    many: []Selection,

    pub fn is(self: *const Selection, comptime kind: SelectionKind, other: switch (kind) {
        .none => void,
        .entity => ecs.Entity,
        .resource => Uuid,
        .many => []Selection,
    }) bool {
        if (kind != std.meta.activeTag(self.*)) {
            return false;
        }

        switch (kind) {
            .none => return true,
            .entity => return self.entity == other,
            .resource => return self.resource.raw == other.raw,
            .many => return false,
        }
    }

    pub fn contains(self: *const Selection, comptime kind: SelectionKind, other: anytype) bool {
        switch (self.*) {
            .none, .entity, .resource => return self.is(kind, other),
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

    pub fn remove(self: *Selection, comptime kind: SelectionKind, other: anytype) bool {
        switch (self.*) {
            .none, .entity, .resource => if (self.is(kind, other)) {
                self.* = .none;
                return true;
            } else {
                return false;
            },
            .many => |ms| return ms.len > 0 and blk: {
                for (ms) |*m| {
                    if (m.is(kind, other)) {
                        m.* = .{ .none = {} };
                        break :blk true;
                    }
                }
                break :blk false;
            },
        }
    }
};

const Self = @This();

ctx: *GameApp,

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
resources_window: ResourcesWindow,
properties_window: PropertiesWindow,
scene_window: SceneWindow,
game_window: GameWindow,
logs_windows: LogsWindow,

pub fn init(ctx: *GameApp) *Self {
    ctx.world.tag(RunInEditor);
    ctx.world.tag(Playing);
    ctx.world.addSingleton(Playing);
    ctx.world.enable(ecs.typeId(Playing), false);
    // const tmu_entity = ctx.world.systemFn("transform-matrix-update", ecs.systems.PostUpdate, ecs.systems.transformMatrices);
    // ctx.world.add(tmu_entity, RunInEditor);
    // _ = ctx.world.observerFn(&ecs.ObserverDesc{
    //     .query = std.mem.zeroInit(ecs.QueryDesc, .{ .terms = .{
    //         .{ .id = ecs.typeId(components.Position) },
    //         .{ .id = ecs.typeId(components.Rotation) },
    //         .{ .id = ecs.typeId(components.Scale) },
    //         .{ .id = ecs.typeId(components.TransformMatrix) },
    //     } }),
    //     .events = [_]ecs.Entity{c.EcsOnSet} ++ [_]ecs.Entity{0} ** 7,
    //     .callback = &struct {
    //         fn f(it: *ecs.Iter) callconv(.C) void {
    //             if (it.event_id == ecs.typeId(components.Position) or
    //                 it.event_id == ecs.typeId(components.Rotation) or
    //                 it.event_id == ecs.typeId(components.Scale))
    //             {
    //                 const positions = ecs.field(@ptrCast(it), components.Position, @alignOf(components.Position), 0).?;
    //                 const rotations = ecs.field(@ptrCast(it), components.Rotation, @alignOf(components.Rotation), 1).?;
    //                 const scales = ecs.field(@ptrCast(it), components.Scale, @alignOf(components.Scale), 2).?;
    //                 const transformMatrices = ecs.field(@ptrCast(it), components.TransformMatrix, @alignOf(components.TransformMatrix), 3).?;
    //                 for (positions, rotations, scales, transformMatrices) |p, r, s, *t| {
    //                     t.value = Mat4.compose(p.value, Quat.fromEuler(r.value), s.value);
    //                 }
    //             }
    //         }
    //     }.f,
    // });

    const home_dir = std.fs.selfExeDirPathAlloc(ctx.allocator) catch @panic("OOM");
    defer ctx.allocator.free(home_dir);
    std.debug.print("{s}\n", .{home_dir});
    std.debug.print("{s}\n", .{home_dir});
    std.debug.print("{s}\n", .{home_dir});
    std.debug.print("{s}\n", .{home_dir});
    std.debug.print("{s}\n", .{home_dir});
    const db_path = std.fs.path.join(ctx.allocator, &[_][]const u8{ home_dir, ".user-data", "db.json" }) catch @panic("OOM");
    defer ctx.allocator.free(db_path);

    EditorDatabase.init(ctx.allocator, db_path) catch @panic("Faield to load editor database");
    inputs = InputsContext{ .window = ctx.window };
    singleton = Self{
        .ctx = ctx,
        .editors = Editors.init(ctx.allocator),
        .hello_modal = HelloModal.init() catch @panic("Failed to initialize `HelloModal`"),
        .new_project_modal = NewProjectModal.init(ctx.allocator) catch @panic("Failed to initialize `NewProjectModal`"),
        .open_project_modal = OpenProjectModal.init(ctx.allocator) catch @panic("Failed to initialize `OpenProjectModal`"),
        .hierarchy_window = HierarchyWindow.init(ctx.allocator),
        .resources_window = ResourcesWindow.init(ctx.allocator) catch @panic("Failed to initialize `ResourcesWindow`"),
        .properties_window = PropertiesWindow.init(ctx.allocator),
        .game_window = GameWindow.init(ctx),
        .logs_windows = LogsWindow.init(ctx.allocator),
        .scene_window = undefined,
    };
    singleton.scene_window = SceneWindow.init(ctx, @ptrCast(&Editors.onDrawGizmos), &singleton.editors);
    singleton.bootstrapEditorPipeline(ctx.world);
    singleton.initDescriptors(&ctx.engine);
    initImGui(&ctx.engine) catch @panic("failed to init imgui");

    if (EditorDatabase.storage().last_open_project) |lop| {
        Project.load(ctx.allocator, lop) catch {
            log.err("Failed to load previously loaded project {s}\n", .{lop});
        };

        if (EditorDatabase.storage().last_open_scene) |los| {
            ctx.loadScene(los) catch |e| {
                log.err("Failed to load previously loaded scene {s} {?}\n", .{ lop, e });
                if (Project.current()) |proj| {
                    EditorDatabase.storage().last_open_scene = proj.default_scene;
                    ctx.loadScene(proj.default_scene) catch |e2| {
                        log.err("Failed to load project's default scene {s} {?}\n", .{ lop, e2 });
                    };
                }
            };
        }
    }

    render_system = ctx.world.systemEx(&.{
        .entity = ctx.world.create("Render"),
        .query = std.mem.zeroInit(c.ecs_query_desc_t, .{ .terms = .{
            .{ .id = c.EcsAny },
        } }),
        .callback = &struct {
            fn f(_: [*c]ecs.Iter) callconv(.C) void {}
        }.f,
    });

    return &singleton;
}

pub fn deinit(self: *Self) void {
    self.editors.deinit();
    self.hello_modal.deinit();
    self.new_project_modal.deinit();
    self.open_project_modal.deinit();
    self.game_window.deinit();
    self.logs_windows.deinit();
    self.hierarchy_window.deinit();
    self.properties_window.deinit();
    self.resources_window.deinit();
    if (Project.current()) |p| {
        p.unload();
    }
    self.ctx.allocator.free(std.mem.span(c.ImGui_GetIO().*.IniFilename));
    loaded_imgui_images.deinit();
    check_vk(c.vkDeviceWaitIdle(self.ctx.engine.device)) catch @panic("Failed to wait for device idle");
    c.cImGui_ImplVulkan_Shutdown();
    EditorDatabase.flush() catch log.err("Failed to flush the editor database\n", .{});
    EditorDatabase.deinit();
}

pub fn windowTitle(self: *Self) ![]u8 {
    const title = "Yume Editor";
    if (Project.current()) |proj| {
        if (self.ctx.scene_handle) |scene| {
            return try std.fmt.allocPrint(self.ctx.allocator, "{s} - {s} - {s}", .{
                proj.project_name,
                Resources.getResourcePath(scene.uuid) catch "UNKNOWN",
                title,
            });
        } else {
            return try std.fmt.allocPrint(self.ctx.allocator, "{s} - {s}", .{
                proj.project_name,
                title,
            });
        }
    } else {
        return try self.ctx.allocator.dupe(u8, title);
    }
}

pub fn newFrame(_: *Self) void {
    inputs.clear();
}

pub fn processEvent(self: *Self, event: *c.SDL_Event) bool {
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
    inputs.push(event);
    if (self.game_window.is_game_window_focused) {
        self.ctx.inputs.push(event);
    }

    return true;
}

pub fn update(self: *Self) !bool {
    Resources.update(self.ctx.delta, self.ctx);
    self.sanitizeSelection(&self.selection);
    try self.scene_window.update(self.ctx);
    return self.ctx.world.progress(self.ctx.delta);
}

pub fn sanitizeSelection(self: *Self, sel: *Selection) void {
    switch (sel.*) {
        .entity => |it| if (!self.ctx.world.isAlive(it)) {
            sel.* = .{ .none = {} };
        },
        .resource => |it| {
            if (!Resources.resourceExists(it)) {
                sel.* = .{ .none = {} };
            }
        },
        .many => |items| {
            var tail: usize = 0;
            for (0..items.len) |i| {
                var it = items[i];
                self.sanitizeSelection(&it);
                if (!it.is(.none, {})) {
                    items[tail] = it;
                    tail += 1;
                }
            }
            std.debug.assert(self.ctx.allocator.resize(items, tail));
        },
        .none => {},
    }
}

pub fn draw(self: *Self) !void {
    const cmd = self.ctx.engine.beginFrame();

    c.cImGui_ImplVulkan_NewFrame();
    c.cImGui_ImplSDL3_NewFrame();
    c.ImGui_NewFrame();

    const io = c.ImGui_GetIO();

    c.ImGuizmo_SetOrthographic(!self.scene_window.is_perspective);
    c.ImGuizmo_BeginFrame();

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
                if (self.ctx.scene_handle) |hndl| {
                    const scene = self.ctx.snapshotLiveScene() catch @panic("Faield to serialize scene");
                    defer scene.deinit();
                    var resource_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const path = Resources.bufResourceFullpath(
                        hndl.uuid,
                        &resource_path_buf,
                    ) catch @panic("Scene not found!");
                    const json = std.json.stringifyAlloc(self.ctx.allocator, scene, .{ .whitespace = .indent_4 }) catch @panic("Failed to serialize the scene");
                    defer self.ctx.allocator.free(json);
                    log.info("saving scene \"{s}\" to save to \"{s}\"\n", .{ hndl.uuid.urn(), path });
                    var file = std.fs.cwd().createFile(path, .{}) catch @panic("Failed to open scene file to save");
                    defer file.close();
                    file.setEndPos(0) catch @panic("Failed to truncate the scene file");
                    file.seekTo(0) catch @panic("Failed to seek the start of the scene file");
                    file.writeAll(json) catch @panic("Failed to write scene data");
                } else {
                    log.warn("Saving new scene not implemented yet\n", .{}); // TODO
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
        if (c.ImGui_ImageButton(
            "Play",
            try getImGuiTexture(if (self.play) "editor://icons/stop.png" else "editor://icons/play.png"),
            c.ImVec2{ .x = 13, .y = 13 },
        )) {
            self.play = !self.play;
            self.ctx.world.enable(ecs.typeId(Playing), self.play);
            self.bootstrapEditorPipeline(self.ctx.world);
        }
        _ = c.ImGui_ImageButton("Pause", try getImGuiTexture("editor://icons/pause.png"), c.ImVec2{ .x = 13, .y = 13 });
        _ = c.ImGui_ImageButton("Next", try getImGuiTexture("editor://icons/fast-forward.png"), c.ImVec2{ .x = 13, .y = 13 });
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
            c.ImGui_DockBuilderDockWindow("Logs", dock_id_down);
            c.ImGui_DockBuilderDockWindow("Resources", dock_id_down);
            c.ImGui_DockBuilderDockWindow("Hierarchy", dock_id_left);
            c.ImGui_DockBuilderDockWindow("Properties", dock_id_right);
            c.ImGui_DockBuilderDockWindow("Game", dockspace_id);
            c.ImGui_DockBuilderDockWindow("Scene", dockspace_id);
            c.ImGui_DockBuilderFinish(dockspace_id);
        }
    }

    c.ImGui_End();

    self.hierarchy_window.draw(self.ctx);
    try self.properties_window.draw(self.ctx);
    try self.resources_window.draw();
    try self.scene_window.draw(cmd, self.ctx);
    self.game_window.draw(cmd, self.ctx);
    try self.logs_windows.draw();

    self.hello_modal.show();
    try self.new_project_modal.show(self.ctx);
    try self.open_project_modal.show(self.ctx);

    c.ImGui_Render();

    // UI
    c.cImGui_ImplVulkan_RenderDrawData(c.ImGui_GetDrawData(), cmd);

    self.ctx.engine.beginPresentRenderPass(cmd);

    self.ctx.engine.endFrame(cmd);
}

fn initDescriptors(self: *Self, engine: *Engine) void {
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

fn initImGui(engine: *Engine) !void {
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

    loaded_imgui_images = std.StringHashMap(c.ImTextureID).init(engine.allocator);

    yume_logo_ds = try getImGuiTexture("editor://icons/yume.png");

    engine.deletion_queue.append(VulkanDeleter.make(imgui_pool, c.vkDestroyDescriptorPool)) catch @panic("Out of memory");

    io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    io.*.ConfigWindowsMoveFromTitleBarOnly = true;

    const root_dir = try rootDir(engine.allocator);
    defer engine.allocator.free(root_dir);
    io.*.IniFilename = try std.fs.path.joinZ(engine.allocator, &[_][]const u8{ root_dir, "imgui.ini" });

    styles.visualStudioStyles();
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

pub fn trySetParentKeepUniquePathName(world: ecs.World, entity: ecs.Entity, new_parent: ecs.Entity, allocator: std.mem.Allocator) !void {
    if (world.getParent(entity)) |parent| {
        if (parent == new_parent) {
            return;
        }
    }
    if (world.hasAncestor(new_parent, entity)) {
        return error.CyclicRelation;
    }

    const old_name = world.getPathName(entity) orelse {
        world.removePair(entity, ecs.relations.ChildOf, ecs.core.Wildcard);
        world.addPair(entity, ecs.relations.ChildOf, new_parent);
        return;
    };

    switch (try makeUniquePathNameIn(world, new_parent, old_name, allocator)) {
        .base => {
            world.removePair(entity, ecs.relations.ChildOf, ecs.core.Wildcard);
            world.addPair(entity, ecs.relations.ChildOf, new_parent);
        },
        .new => |new| {
            defer allocator.free(new);
            const message = try std.fmt.allocPrintZ(allocator,
                \\Do you want to rename "{s}" to "{s}"?
                \\
                \\There is already an entity with the same path name.
            , .{ old_name, new });
            defer allocator.free(message);
            const selected = try messageBox(.{
                .title = "Rename Entity",
                .message = message,
                .kind = .warn,
            });
            if (selected == 1) {
                return error.Cancel;
            }
            _ = world.setPathName(entity, null);
            _ = world.removePair(entity, ecs.relations.ChildOf, ecs.core.Wildcard);
            _ = world.addPair(entity, ecs.relations.ChildOf, new_parent);
            _ = world.setPathName(entity, new);
        },
    }
}

pub fn trySetUniquePathName(world: ecs.World, entity: ecs.Entity, new_name: ?[*:0]const u8, allocator: std.mem.Allocator) !ecs.Entity {
    if (new_name) |name| {
        const old_name = world.getPathName(entity);
        if (old_name != null and std.mem.eql(u8, old_name.?, std.mem.span(name))) {
            return entity;
        }

        const parent = world.getParent(entity) orelse 0;
        switch (try makeUniquePathNameIn(world, parent, name, allocator)) {
            .base => |base| {
                return world.setPathName(entity, base);
            },
            .new => |new| {
                defer allocator.free(new);
                const message = try std.fmt.allocPrintZ(allocator,
                    \\Do you want to rename "{s}" to "{s}"?
                    \\
                    \\There is already an entity with the same path name.
                , .{ name, new });
                defer allocator.free(message);
                const selected = try messageBox(.{
                    .title = "Rename Entity",
                    .message = message,
                    .kind = .warn,
                });
                if (selected == 1) {
                    return error.Cancel;
                }
                return world.setPathName(entity, new);
            },
        }
    } else {
        return world.setPathName(entity, null);
    }
}

pub fn makeUniquePathNameIn(world: ecs.World, parent: ecs.Entity, base_name: [*:0]const u8, allocator: std.mem.Allocator) !UniquePathName {
    var collision = world.lookupEx(.{ .parent = parent, .path = base_name });
    log.debug("check for {s} collision: {d}\n", .{ base_name, collision });
    if (collision == 0) {
        return .{ .base = std.mem.span(base_name) };
    }

    var sfa = std.heap.stackFallback(512, allocator);
    const a = sfa.get();
    const buf: []u8 = try a.alloc(u8, std.mem.span(base_name).len + 9);
    defer a.free(buf);
    var suffixed: [:0]u8 = undefined;
    var i: usize = 1;
    while (collision != 0) : (i += 1) {
        suffixed = try std.fmt.bufPrintZ(buf, "{s} ({d})", .{ base_name, i });
        collision = world.lookupEx(.{ .parent = parent, .path = suffixed });
    }
    return .{ .new = try allocator.dupeZ(u8, suffixed) };
}

const UniquePathName = union(enum) {
    base: [:0]const u8,
    new: [:0]u8,
};

pub fn messageBox(opts: struct {
    title: [*:0]const u8,
    message: [*:0]const u8,
    buttons: []const c.SDL_MessageBoxButtonData = &[2]c.SDL_MessageBoxButtonData{
        .{ .buttonID = 0, .text = "Ok", .flags = c.SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT },
        .{ .buttonID = 1, .text = "Cancel", .flags = c.SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT },
    },
    kind: enum(u32) {
        default = 0,
        err = c.SDL_MESSAGEBOX_ERROR,
        warn = c.SDL_MESSAGEBOX_WARNING,
        info = c.SDL_MESSAGEBOX_INFORMATION,
    } = .default,
}) !usize {
    var button: c_int = 0;
    if (!c.SDL_ShowMessageBox(&.{
        .flags = @intFromEnum(opts.kind),
        .window = Self.instance().ctx.window,
        .title = opts.title,
        .message = opts.message,
        .numbuttons = @intCast(opts.buttons.len),
        .buttons = &opts.buttons[0],
    }, &button)) {
        return error.FailedToOpenMessageBox;
    }

    return @intCast(button);
}

pub fn getImGuiTexture(uri: []const u8) !c.ImTextureID {
    var engine = &instance().ctx.engine;
    const entry = try loaded_imgui_images.getOrPut(uri);
    errdefer if (!entry.found_existing) {
        _ = loaded_imgui_images.remove(uri);
    };
    if (entry.found_existing) {
        return entry.value_ptr.*;
    }
    const image = try Assets.getOrLoadImage(try Resources.getResourceId(uri));

    // Create the Image View
    var image_view: c.VkImageView = undefined;
    {
        const info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image.image,
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
    entry.value_ptr.* = @intFromPtr(c.cImGui_ImplVulkan_AddTexture(sampler, image_view, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL));
    return entry.value_ptr.*;
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

var singleton: Self = undefined;

pub var render_system: ecs.Entity = undefined;

pub var inputs: InputsContext = undefined;

pub var roboto14: *c.ImFont = undefined;
pub var roboto24: *c.ImFont = undefined;
pub var roboto32: *c.ImFont = undefined;

// assets

pub var loaded_imgui_images: std.StringHashMap(c.ImTextureID) = undefined;

pub var yume_logo_ds: c.ImTextureID = undefined;

fn frustum(left: f32, right: f32, bottom: f32, top: f32, znear: f32, zfar: f32, m16: *[16]f32) void {
    const temp = 2 * znear;
    const temp2 = right - left;
    const temp3 = top - bottom;
    const temp4 = zfar - znear;
    m16.*[0] = temp / temp2;
    m16.*[1] = 0.0;
    m16.*[2] = 0.0;
    m16.*[3] = 0.0;
    m16.*[4] = 0.0;
    m16.*[5] = temp / temp3;
    m16.*[6] = 0.0;
    m16.*[7] = 0.0;
    m16.*[8] = (right + left) / temp2;
    m16.*[9] = (top + bottom) / temp3;
    m16.*[10] = (-zfar - znear) / temp4;
    m16.*[11] = -1;
    m16.*[12] = 0.0;
    m16.*[13] = 0.0;
    m16.*[14] = (-temp * zfar) / temp4;
    m16.*[15] = 0.0;
}

fn perspective(fovyInDegrees: f32, aspectRatio: f32, znear: f32, zfar: f32, m16: *[16]f32) void {
    const ymax = znear * @tan(fovyInDegrees * 3.141592 / 180);
    const xmax = ymax * aspectRatio;
    frustum(-xmax, xmax, -ymax, ymax, znear, zfar, m16);
}

fn getForwardDirection(transformMatrix: Mat4) Vec3 {
    // Extract the basis vectors directly from the rotation part of the transform matrix.
    const forward = Vec3.make(-transformMatrix.unnamed[2][0], // Negative Z in world space
        -transformMatrix.unnamed[2][1], -transformMatrix.unnamed[2][2]);

    return forward.normalized(); // Normalize the vector to ensure unit length
}

pub fn rootDir(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    return allocator.dupe(u8, try bufRootDir(&buf));
}

pub fn bufRootDir(buf: []u8) ![]const u8 {
    const exe_path = try std.fs.selfExeDirPath(buf);
    return std.fs.path.dirname(exe_path) orelse return error.InvalidPath;
}
