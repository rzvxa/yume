const c = @import("clibs");

const std = @import("std");

const check_vk = @import("yume").vki.check_vk;

const GameApp = @import("yume").GameApp;
const AllocatedBuffer = @import("yume").AllocatedBuffer;
const FRAME_OVERLAP = @import("yume").FRAME_OVERLAP;
const GPUCameraData = @import("yume").GPUCameraData;
const GPUSceneData = @import("yume").GPUSceneData;
const VmaBufferDeleter = @import("yume").VmaBufferDeleter;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("Leaked memory");
    };

    var cwd_buff: [1024]u8 = undefined;
    const cwd = std.process.getCwd(cwd_buff[0..]) catch @panic("cwd_buff too small");
    std.log.info("Running from: {s}", .{cwd});

    var app = GameApp.init(gpa.allocator(), "Yume Editor");
    defer app.cleanup();

    app.run(struct {
        play: bool = false,
        imgui_demo_open: bool = false,

        dockspace_flags: c.ImGuiDockNodeFlags = 0,

        editor_camera_and_scene_buffer: AllocatedBuffer = undefined,
        editor_camera_and_scene_set: c.VkDescriptorSet = null,

        pub fn init(ctx: *GameApp) @This() {
            var ed = @This(){};
            var eng = ctx.engine;

            const camera_and_scene_buffer_size =
                FRAME_OVERLAP * eng.pad_uniform_buffer_size(@sizeOf(GPUCameraData)) +
                FRAME_OVERLAP * eng.pad_uniform_buffer_size(@sizeOf(GPUSceneData));
            ed.editor_camera_and_scene_buffer = eng.create_buffer(camera_and_scene_buffer_size, c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
            eng.buffer_deletion_queue.append(VmaBufferDeleter{ .buffer = ed.editor_camera_and_scene_buffer }) catch @panic("Out of memory");

            // Camera and scene descriptor set
            const global_set_alloc_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
                .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                .descriptorPool = eng.descriptor_pool,
                .descriptorSetCount = 1,
                .pSetLayouts = &eng.global_set_layout,
            });

            // Allocate a single set for multiple frame worth of camera and scene data
            check_vk(c.vkAllocateDescriptorSets(eng.device, &global_set_alloc_info, &ed.editor_camera_and_scene_set)) catch @panic("Failed to allocate global descriptor set");

            // editor Camera
            const editor_camera_buffer_info = std.mem.zeroInit(c.VkDescriptorBufferInfo, .{
                .buffer = ed.editor_camera_and_scene_buffer.buffer,
                .range = @sizeOf(GPUCameraData),
            });

            const editor_camera_write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = ed.editor_camera_and_scene_set,
                .dstBinding = 0,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
                .pBufferInfo = &editor_camera_buffer_info,
            });

            // editor Scene parameters
            const editor_scene_parameters_buffer_info = std.mem.zeroInit(c.VkDescriptorBufferInfo, .{
                .buffer = ed.editor_camera_and_scene_buffer.buffer,
                .range = @sizeOf(GPUSceneData),
            });

            const editor_scene_parameters_write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = ed.editor_camera_and_scene_set,
                .dstBinding = 1,
                .descriptorCount = 1,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC,
                .pBufferInfo = &editor_scene_parameters_buffer_info,
            });

            const editor_camera_and_scene_writes = [_]c.VkWriteDescriptorSet{
                editor_camera_write,
                editor_scene_parameters_write,
            };

            c.vkUpdateDescriptorSets(eng.device, @as(u32, @intCast(editor_camera_and_scene_writes.len)), &editor_camera_and_scene_writes[0], 0, null);

            return ed;
        }

        pub fn processEvent(_: *@This(), ctx: *GameApp, event: *c.SDL_Event) bool {
            const mouse = ctx.mouse;

            _ = c.cImGui_ImplSDL3_ProcessEvent(event);
            if (event.type == c.SDL_EVENT_QUIT) {
                return false;
            } else if (ctx.engine.is_game_window_active and ctx.engine.isInGameView(mouse)) {
                ctx.engine.processGameEvent(event);
            } else if (ctx.engine.is_scene_window_active and ctx.engine.isInSceneView(mouse)) {
                ctx.engine.processGameEvent(event);
            } else {
                ctx.engine.camera_input.x = 0;
                ctx.engine.camera_input.y = 0;
                ctx.engine.camera_input.z = 0;
            }

            return true;
        }

        pub fn update(_: *@This(), _: *GameApp) void {}

        pub fn draw(self: *@This(), ctx: *GameApp) void {
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
                if (c.ImGui_ImageButton("Play", if (self.play) ctx.engine.stop_icon_ds else ctx.engine.play_icon_ds, c.ImVec2{ .x = 13, .y = 13 })) {
                    self.play = !self.play;
                }
                _ = c.ImGui_ImageButton("Pause", ctx.engine.pause_icon_ds, c.ImVec2{ .x = 13, .y = 13 });
                _ = c.ImGui_ImageButton("Next", ctx.engine.fast_forward_icon_ds, c.ImVec2{ .x = 13, .y = 13 });
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

                if (ctx.engine.first_time) {
                    ctx.engine.first_time = false;

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
            for (ctx.engine.renderables.items) |r| {
                var node_flags = c.ImGuiTreeNodeFlags_OpenOnArrow;
                if (std.mem.eql(u8, std.mem.span(r.name), "triangle")) {
                    node_flags = c.ImGuiTreeNodeFlags_Leaf;
                }
                if (c.ImGui_TreeNodeEx(r.name, node_flags)) {
                    c.ImGui_TreePop();
                }
            }
            c.ImGui_End();

            _ = c.ImGui_Begin("Assets", null, 0);
            c.ImGui_Text("TODO");
            c.ImGui_End();

            _ = c.ImGui_Begin("Properties", null, 0);
            c.ImGui_Text("TODO");
            c.ImGui_End();

            _ = c.ImGui_Begin("Game", null, 0);
            const old_is_game_window_focused = ctx.engine.is_game_window_focused;
            ctx.engine.is_game_window_focused = c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_None);
            if (ctx.engine.is_game_window_focused) {
                if (!old_is_game_window_focused) {
                    ctx.engine.is_game_window_active = true;
                } else if (ctx.engine.isInGameView(c.ImGui_GetMousePos()) and c.ImGui_IsMouseClicked(c.ImGuiMouseButton_Left)) {
                    ctx.engine.is_game_window_active = true;
                }
            } else {
                ctx.engine.is_game_window_active = false;
            }
            const game_image = c.ImGui_GetWindowDrawList();
            ctx.engine.game_view_size = c.ImGui_GetWindowSize();
            const DispatcherType = @This();
            const FrameData = struct { app: *GameApp, cmd: GameApp.RenderCommand, d: *DispatcherType };
            var frame_userdata = FrameData{ .app = ctx, .cmd = cmd, .d = self };
            c.ImDrawList_AddCallback(game_image, extern struct {
                fn f(dl: [*c]const c.ImDrawList, dc: [*c]const c.ImDrawCmd) callconv(.C) void {
                    _ = dl;
                    const me: *FrameData = @alignCast(@ptrCast(dc.*.UserCallbackData));
                    // const cmd = me.get_current_frame().main_command_buffer;
                    const cr = dc.*.ClipRect;
                    me.app.engine.game_window_rect = cr;
                    const w = cr.z - cr.x;
                    const h = cr.w - cr.y;

                    me.app.engine.beginAdditiveRenderPass(me.cmd);

                    c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                        .offset = .{ .x = @intFromFloat(cr.x), .y = @intFromFloat(cr.y) },
                        .extent = .{ .width = @intFromFloat(w), .height = @intFromFloat(h) },
                    }});

                    const vx = if (cr.x > 0) cr.x else cr.z - me.app.engine.game_view_size.x;
                    c.vkCmdSetViewport(me.cmd, 0, 1, &[_]c.VkViewport{.{
                        .x = vx,
                        .y = cr.y,
                        .width = me.app.engine.game_view_size.x,
                        .height = me.app.engine.game_view_size.y,
                        .minDepth = 0.0,
                        .maxDepth = 1.0,
                    }});

                    const aspect = me.app.engine.game_view_size.x / me.app.engine.game_view_size.y;
                    std.log.debug("draw eng", .{});
                    me.app.engine.draw_objects(me.cmd, me.app.engine.renderables.items, aspect, me.app.engine.camera_and_scene_buffer, me.app.engine.camera_and_scene_set);

                    c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                        .offset = .{ .x = 0, .y = 0 },
                        .extent = GameApp.window_extent,
                    }});
                }
            }.f, &frame_userdata);
            c.ImDrawList_AddCallback(game_image, c.ImDrawCallback_ResetRenderState, null);
            c.ImGui_End();

            _ = c.ImGui_Begin("Scene", null, 0);
            const old_is_scene_window_focused = ctx.engine.is_scene_window_focused;
            ctx.engine.is_scene_window_focused = c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_None);
            if (ctx.engine.is_scene_window_focused) {
                if (!old_is_scene_window_focused) {
                    ctx.engine.is_scene_window_active = true;
                } else if (ctx.engine.isInSceneView(c.ImGui_GetMousePos()) and c.ImGui_IsMouseClicked(c.ImGuiMouseButton_Left)) {
                    ctx.engine.is_scene_window_active = true;
                }
            } else {
                ctx.engine.is_scene_window_active = false;
            }
            const editor_image = c.ImGui_GetWindowDrawList();
            ctx.engine.scene_view_size = c.ImGui_GetWindowSize();

            c.ImDrawList_AddCallback(editor_image, extern struct {
                fn f(dl: [*c]const c.ImDrawList, dc: [*c]const c.ImDrawCmd) callconv(.C) void {
                    _ = dl;
                    const me: *FrameData = @alignCast(@ptrCast(dc.*.UserCallbackData));
                    const cr = dc.*.ClipRect;
                    me.app.engine.scene_window_rect = cr;
                    const w = cr.z - cr.x;
                    const h = cr.w - cr.y;

                    me.app.engine.beginAdditiveRenderPass(me.cmd);
                    c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                        .offset = .{ .x = @intFromFloat(cr.x), .y = @intFromFloat(cr.y) },
                        .extent = .{ .width = @intFromFloat(w), .height = @intFromFloat(h) },
                    }});

                    const vx = if (cr.x > 0) cr.x else cr.z - me.app.engine.scene_view_size.x;
                    c.vkCmdSetViewport(me.cmd, 0, 1, &[_]c.VkViewport{.{
                        .x = vx,
                        .y = cr.y,
                        .width = me.app.engine.scene_view_size.x,
                        .height = me.app.engine.scene_view_size.y,
                        .minDepth = 0.0,
                        .maxDepth = 1.0,
                    }});

                    const aspect = me.app.engine.scene_view_size.x / me.app.engine.scene_view_size.y;
                    me.app.engine.draw_objects(me.cmd, me.app.engine.renderables.items, aspect, me.d.editor_camera_and_scene_buffer, me.d.editor_camera_and_scene_set);

                    c.vkCmdSetScissor(me.cmd, 0, 1, &[_]c.VkRect2D{.{
                        .offset = .{ .x = 0, .y = 0 },
                        .extent = GameApp.window_extent,
                    }});
                }
            }.f, &frame_userdata);
            c.ImDrawList_AddCallback(editor_image, c.ImDrawCallback_ResetRenderState, null);
            c.ImGui_End();

            c.ImGui_Render();

            // UI
            c.cImGui_ImplVulkan_RenderDrawData(c.ImGui_GetDrawData(), cmd);

            ctx.engine.beginPresentRenderPass(cmd);

            ctx.engine.endFrame(cmd);
        }
    });
}
