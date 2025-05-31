const c = @import("clibs");

const std = @import("std");
const log = std.log.scoped(.Editor);

const gizmo = @import("gizmo.zig");

const Uuid = @import("yume").Uuid;
const EditorDatabase = @import("EditorDatabase.zig");
const Editors = @import("editors/editors.zig");
const Resources = @import("Resources.zig");
const Project = @import("Project.zig");
const Assets = @import("yume").Assets;
const assets = @import("yume").assets;

const HierarchyWindow = @import("windows/HierarchyWindow.zig");
const ResourcesWindow = @import("windows/ResourcesWindow.zig");
const PropertiesWindow = @import("windows/PropertiesWindow.zig");
const SceneWindow = @import("windows/SceneWindow.zig");
const GameWindow = @import("windows/GameWindow.zig");
const LogsWindow = @import("windows/LogsWindow.zig");

const ProjectExplorerWindow = @import("windows/ProjectExplorerWindow.zig");

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

const GAL = @import("yume").GAL;
const check_vk = GAL.RenderApi.check_vk;

const NewProjectModal = @import("modals/NewProjectModal.zig");
const OpenProjectModal = @import("modals/OpenProjectModal.zig");
const HelloModal = @import("modals/HelloModal.zig");
const AboutModal = @import("modals/AboutModal.zig");

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

hello_modal: HelloModal,
about_modal: AboutModal,
new_project_modal: NewProjectModal,
open_project_modal: OpenProjectModal,

hierarchy_window: HierarchyWindow,
resources_window: ResourcesWindow,
properties_window: PropertiesWindow,
scene_window: SceneWindow,
game_window: GameWindow,
logs_windows: LogsWindow,

project_explorer_window: ProjectExplorerWindow,

callbacks_arena: std.heap.ArenaAllocator,

pub fn init(ctx: *GameApp) !*Self {
    ctx.world.tag(RunInEditor);
    ctx.world.tag(Playing);
    ctx.world.addSingleton(Playing);
    ctx.world.enable(ecs.typeId(Playing), false);
    {
        const tss = ecs.systems.TransformSyncSystem.registerTo(ctx.world);
        ctx.world.add(tss, RunInEditor);
        ctx.world.add(
            ecs.systems.PostTransformSystem.registerTo(ctx.world, .world, tss),
            RunInEditor,
        );
        ctx.world.add(
            ecs.systems.PostTransformSystem.registerTo(ctx.world, .local, tss),
            RunInEditor,
        );
    }

    const home_dir = try std.fs.selfExeDirPathAlloc(ctx.allocator);
    defer ctx.allocator.free(home_dir);
    const db_path = try std.fs.path.join(ctx.allocator, &[_][]const u8{ home_dir, ".user-data", "db.json" });
    defer ctx.allocator.free(db_path);

    try EditorDatabase.init(ctx.allocator, db_path);
    inputs = InputsContext{ .window = ctx.window };
    singleton = Self{
        .ctx = ctx,
        .editors = Editors.init(ctx.allocator),
        .hello_modal = try HelloModal.init(),
        .about_modal = try AboutModal.init(ctx.allocator),
        .new_project_modal = try NewProjectModal.init(ctx.allocator),
        .open_project_modal = try OpenProjectModal.init(ctx.allocator),
        .hierarchy_window = HierarchyWindow.init(ctx.allocator),
        .resources_window = try ResourcesWindow.init(ctx.allocator),
        .properties_window = PropertiesWindow.init(ctx.allocator),
        .game_window = GameWindow.init(ctx),
        .logs_windows = try LogsWindow.init(ctx.allocator),
        .project_explorer_window = try ProjectExplorerWindow.init(ctx.allocator),
        .scene_window = undefined,
        .callbacks_arena = std.heap.ArenaAllocator.init(ctx.allocator),
    };
    singleton.scene_window = try SceneWindow.init(ctx, @ptrCast(&Editors.onDrawGizmos), &singleton.editors);
    singleton.bootstrapEditorPipeline(ctx.world);

    try initImGui(&ctx.renderer);

    try singleton.project_explorer_window.setup();

    if (EditorDatabase.storage().project.last_open_project) |lop| {
        Project.load(ctx.allocator, lop) catch {
            log.err("Failed to load previously loaded project {s}\n", .{lop});
        };

        if (EditorDatabase.storage().project.last_open_scene) |los| {
            singleton.openScene(los) catch |e| {
                log.err("Failed to load previously loaded scene {s} {?}\n", .{ lop, e });
                if (Project.current()) |proj| {
                    EditorDatabase.storage().project.last_open_scene = proj.default_scene;
                    singleton.openScene(proj.default_scene) catch |e2| {
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
    self.about_modal.deinit();
    self.new_project_modal.deinit();
    self.open_project_modal.deinit();
    self.game_window.deinit();
    self.logs_windows.deinit();
    self.project_explorer_window.deinit();
    self.hierarchy_window.deinit();
    self.properties_window.deinit();
    self.resources_window.deinit();
    if (Project.current()) |p| {
        p.unload();
    }
    self.ctx.allocator.free(std.mem.span(c.ImGui_GetIO().*.IniFilename));
    EditorDatabase.flush() catch log.err("Failed to flush the editor database\n", .{});
    EditorDatabase.deinit();

    check_vk(c.vkDeviceWaitIdle(self.ctx.renderer.device)) catch @panic("Failed to wait for device idle");
    c.cImGui_ImplVulkan_Shutdown();
    {
        var iter = loaded_imgui_images.iterator();
        while (iter.next()) |next| {
            Assets.release(next.value_ptr.handle) catch {};
        }
        loaded_imgui_images.deinit();
    }

    self.callbacks_arena.deinit();
}

pub fn windowTitle(self: *Self) ![]u8 {
    const title = "Yume Editor";
    if (Project.current()) |proj| {
        if (self.ctx.scene.handle) |scene| {
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
    const cmd = self.ctx.renderer.beginFrame();

    imutils.newFrame();

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
                if (self.ctx.scene.handle) |hndl| {
                    const scene = try self.ctx.snapshotLiveScene();
                    defer scene.deinit();
                    var resource_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const path = try Resources.bufResourceFullpath(
                        hndl.uuid,
                        &resource_path_buf,
                    );
                    const json = try std.json.stringifyAlloc(self.ctx.allocator, scene, .{ .whitespace = .indent_4 });
                    defer self.ctx.allocator.free(json);
                    log.info("saving scene \"{s}\" to save to \"{s}\"\n", .{ hndl.uuid.urn(), path });
                    var file = try std.fs.cwd().createFile(path, .{});
                    defer file.close();
                    try file.setEndPos(0);
                    try file.seekTo(0);
                    try file.writeAll(json);
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
            if (c.ImGui_MenuItem("About")) {
                self.about_modal.open();
            }
            c.ImGui_EndMenu();
        }
        c.ImGui_SetCursorPosX(
            (c.ImGui_GetCursorPosX() - (13 * 3)) +
                (@as(f32, @floatFromInt(self.ctx.windowExtent().x)) / 2) -
                c.ImGui_GetCursorPosX(),
        );
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

    const viewport = c.ImGui_GetMainViewport();
    const dockspace_id = c.ImGui_GetID("MainDockSpace");

    if (c.ImGui_DockBuilderGetNode(dockspace_id) == null) {
        _ = c.ImGui_DockBuilderAddNodeEx(dockspace_id, self.dockspace_flags | c.ImGuiDockNodeFlags_DockSpace);
        c.ImGui_DockBuilderSetNodeSize(dockspace_id, viewport.*.Size);

        var dockspace_id_copy = dockspace_id;
        const dock_id_left = c.ImGui_DockBuilderSplitNode(dockspace_id_copy, c.ImGuiDir_Left, 0.2, null, &dockspace_id_copy);
        const dock_id_right = c.ImGui_DockBuilderSplitNode(dockspace_id_copy, c.ImGuiDir_Right, 0.2, null, &dockspace_id_copy);
        const dock_id_down = c.ImGui_DockBuilderSplitNode(dockspace_id_copy, c.ImGuiDir_Down, 0.25, null, &dockspace_id_copy);

        c.ImGui_DockBuilderDockWindow("Resources", dock_id_down);
        c.ImGui_DockBuilderDockWindow("Logs", dock_id_down);
        c.ImGui_DockBuilderDockWindow("Hierarchy", dock_id_left);
        c.ImGui_DockBuilderDockWindow("Properties", dock_id_right);
        c.ImGui_DockBuilderDockWindow("Game", dockspace_id_copy);
        c.ImGui_DockBuilderDockWindow("Scene", dockspace_id_copy);
        c.ImGui_DockBuilderFinish(dockspace_id_copy);
    }

    _ = c.ImGui_DockSpaceOverViewportEx(dockspace_id, viewport, 0, null);

    try self.project_explorer_window.draw(self.ctx);

    try self.resources_window.draw();
    self.hierarchy_window.draw(self.ctx);
    try self.properties_window.draw(self.ctx);
    try self.scene_window.draw(cmd, self.ctx);
    self.game_window.draw(cmd, self.ctx);
    try self.logs_windows.draw();

    self.hello_modal.draw();
    try self.about_modal.draw();
    try self.new_project_modal.draw(self.ctx);
    try self.open_project_modal.draw(self.ctx);

    imutils.render();

    // UI
    c.cImGui_ImplVulkan_RenderDrawData(c.ImGui_GetDrawData(), cmd);

    self.ctx.renderer.beginPresentRenderPass(cmd);

    self.ctx.renderer.endFrame(cmd);
}

fn initImGui(renderer: *GAL.RenderApi) !void {
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
    try check_vk(c.vkCreateDescriptorPool(renderer.device, &pool_ci, GAL.RenderApi.vk_alloc_cbs, &imgui_pool));

    imutils.createContext();
    _ = c.cImGui_ImplSDL3_InitForVulkan(renderer.window);

    var init_info = std.mem.zeroInit(c.ImGui_ImplVulkan_InitInfo, .{
        .Instance = renderer.instance,
        .PhysicalDevice = renderer.physical_device,
        .Device = renderer.device,
        .RenderPass = renderer.render_pass,
        .QueueFamily = renderer.graphics_queue_family,
        .Queue = renderer.graphics_queue,
        .DescriptorPool = imgui_pool,
        .MinImageCount = GAL.frame_overlap,
        .ImageCount = GAL.frame_overlap,
        .MSAASamples = c.VK_SAMPLE_COUNT_1_BIT,
    });

    const io = c.ImGui_GetIO();
    // TODO: load fonts as assets similar to imgui textures
    ubuntu14 = c.ImFontAtlas_AddFontFromFileTTF(io.*.Fonts, "resources/editor/fonts/UbuntuNerdFontPropo-Regular.ttf", 14, null, &nerd_font_glyphs);
    ubuntu24 = c.ImFontAtlas_AddFontFromFileTTF(io.*.Fonts, "resources/editor/fonts/UbuntuNerdFontPropo-Regular.ttf", 24, null, &nerd_font_glyphs);
    ubuntu32 = c.ImFontAtlas_AddFontFromFileTTF(io.*.Fonts, "resources/editor/fonts/UbuntuNerdFontPropo-Regular.ttf", 32, null, &nerd_font_glyphs);

    _ = c.cImGui_ImplVulkan_Init(&init_info);
    _ = c.cImGui_ImplVulkan_CreateFontsTexture();

    loaded_imgui_images = std.StringHashMap(LoadedImGuiImage).init(renderer.allocator);

    yume_logo_ds = try getImGuiTexture("editor://icons/yume.png");

    try renderer.deletion_queue.append(
        GAL.RenderApi.VulkanDeleter.make(imgui_pool, c.vkDestroyDescriptorPool),
    );

    io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    io.*.ConfigWindowsMoveFromTitleBarOnly = true;

    const root_dir = try rootDir(renderer.allocator);
    defer renderer.allocator.free(root_dir);
    io.*.IniFilename = try std.fs.path.joinZ(renderer.allocator, &[_][]const u8{ root_dir, "imgui.ini" });

    styles.defaultStyles();
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

pub fn openScene(self: *Self, scene: assets.SceneHandle) !void {
    switch (self.selection) {
        .entity => self.selection = .none,
        else => {},
    }
    try self.ctx.loadScene(scene);
    EditorDatabase.storage().project.last_open_scene = scene;
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
        world.modified(entity, ecs.components.WorldTransform);
        return;
    };

    switch (try makeUniquePathNameIn(world, new_parent, old_name, allocator)) {
        .base => {
            world.removePair(entity, ecs.relations.ChildOf, ecs.core.Wildcard);
            world.addPair(entity, ecs.relations.ChildOf, new_parent);
            world.modified(entity, ecs.components.WorldTransform);
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
            world.modified(entity, ecs.components.WorldTransform);
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
    const CbType = struct {
        uri: []const u8,
        fn f(ptr: *@This(), handle: assets.AssetHandle) void {
            _ = handle;
            const entry = loaded_imgui_images.fetchRemove(ptr.uri).?;

            c.cImGui_ImplVulkan_RemoveTexture(@ptrFromInt(entry.value.texture));
            Assets.release(entry.value.handle) catch {};
            instance().callbacks_arena.allocator().destroy(ptr);
        }
    };

    const entry = try loaded_imgui_images.getOrPut(uri);
    errdefer if (!entry.found_existing) {
        _ = loaded_imgui_images.remove(uri);
    };
    if (entry.found_existing) {
        return entry.value_ptr.texture;
    }

    const texture = try Assets.get((try Resources.getAssetHandle(uri, .{ .expect = .image })).toTexture());
    const cb_instance = try instance().callbacks_arena.allocator().create(CbType);
    errdefer instance().callbacks_arena.allocator().destroy(cb_instance);
    cb_instance.* = .{ .uri = uri };

    const hooks = try Assets.hooks(texture.handle.toAssetHandle());
    try hooks.on_reload.append(.once, assets.AssetHooks.OnReload.callback(
        CbType,
        cb_instance,
        &CbType.f,
    ));

    const texture_ptr = @intFromPtr(c.cImGui_ImplVulkan_AddTexture(texture.sampler, texture.image_view, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL));
    entry.value_ptr.* = .{
        .handle = texture.handle.toAssetHandle(),
        .texture = texture_ptr,
    };
    return texture_ptr;
}

fn bootstrapEditorPipeline(self: *const Self, world: ecs.World) void {
    var query = c.ecs_query_desc_t{};
    query.terms[0] = .{ .id = ecs.core.System };
    query.terms[1] = .{
        .id = ecs.systems.Phase,
        .src = .{ .id = ecs.query_miscs.Cascade },
        .trav = ecs.relations.DependsOn,
    };
    query.terms[2] = .{
        .id = c.ecs_dependson(ecs.systems.OnStart),
        .trav = ecs.relations.DependsOn,
        .oper = ecs.operators.Not,
    };
    query.terms[3] = .{
        .id = ecs.scopes.Disabled,
        .src = .{ .id = ecs.query_miscs.Up },
        .trav = ecs.relations.DependsOn,
        .oper = ecs.operators.Not,
    };
    query.terms[4] = .{
        .id = ecs.scopes.Disabled,
        .src = .{ .id = ecs.query_miscs.Up },
        .trav = ecs.relations.ChildOf,
        .oper = ecs.operators.Not,
    };
    if (!self.play) {
        query.terms[5] = .{
            .id = ecs.typeId(RunInEditor),
            .src = .{ .id = ecs.query_miscs.Self },
        };
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

fn flecs_entity_compare(e1: c.ecs_entity_t, _: ?*const anyopaque, e2: c.ecs_entity_t, _: ?*const anyopaque) callconv(.C) c_int {
    return @as(c_int, @intCast(@intFromBool((e1 > e2)))) - @intFromBool((e1 < e2));
}

var singleton: Self = undefined;

pub var render_system: ecs.Entity = undefined;

pub var inputs: InputsContext = undefined;

pub var ubuntu14: *c.ImFont = undefined;
pub var ubuntu24: *c.ImFont = undefined;
pub var ubuntu32: *c.ImFont = undefined;

const LoadedImGuiImage = struct {
    handle: assets.AssetHandle,
    texture: c.ImTextureID,
};
var loaded_imgui_images: std.StringHashMap(LoadedImGuiImage) = undefined;

pub var yume_logo_ds: c.ImTextureID = undefined;

pub fn rootDir(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    return allocator.dupe(u8, try bufRootDir(&buf));
}

pub fn bufRootDir(buf: []u8) ![]const u8 {
    const exe_path = try std.fs.selfExeDirPath(buf);
    return std.fs.path.dirname(exe_path) orelse return error.InvalidPath;
}

const nerd_font_glyphs = [_]c.ImWchar{
    0x0020, 0x00ff, // Basic Latin + Latin Supplement
    //IEC Power Symbols
    0x23fb, 0x23fe,
    //IEC Power Symbols
    0x2b58, 0x2b58,
    //Pomicons
    0xe000, 0xe00a,
    //Powerline
    0xe0a0, 0xe0a2,
    //Powerline
    0xe0b0, 0xe0b3,
    //Powerline Extra
    0xe0b4, 0xe0c8,
    //Powerline Extra
    0xe0a3, 0xe0a3,
    //Powerline Extra
    0xe0ca, 0xe0ca,
    //Powerline Extra
    0xe0cc, 0xe0d7,
    //Weather Icons
    0xe300, 0xe3e3,
    //Seti-UI + Custom
    0xe5fa, 0xe6b7,
    //Devicons
    0xe700, 0xe8ef,
    //Codicons
    0xea60, 0xec1e,
    //Font Awesome
    0xed00, 0xefce,
    //Font Awesome
    0xf000, 0xf2ff,
    //Font Logos
    0xf300, 0xf381,
    //Font Awesome Extension
    0xe200, 0xe2a9,
    //Octicons
    0xf400, 0xf533,
    //Octicons
    0x2665, 0x2665,
    //Octicons
    0x26a1, 0x26a1,
    //Material Design
    0xf500, 0xfd46,
    0, // null termination
};
