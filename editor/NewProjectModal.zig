const c = @import("clibs");

const builtin = @import("builtin");
const std = @import("std");

const Uuid = @import("yume").Uuid;
const Scene = @import("yume").scene_graph.Scene;

const GameApp = @import("yume").GameApp;
const Engine = @import("yume").VulkanEngine;
const VulkanDeleter = @import("yume").VulkanDeleter;
const check_vk = @import("yume").vki.check_vk;
const Camera = @import("yume").Camera;
const MeshRenderer = @import("yume").MeshRenderer;
const AssetsDatabase = @import("yume").AssetsDatabase;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;

const imutils = @import("imutils.zig");
const Editor = @import("Editor.zig");
const Project = @import("Project.zig");
const utils = @import("yume").utils;

const Self = @This();

allocator: std.mem.Allocator,

id: c.ImGuiID = undefined,
is_open: bool = false,

project_name: std.ArrayList(u8),
project_path: std.ArrayList(u8),

const yume_projects_root = switch (builtin.os.tag) {
    .windows => "Documents\\Yume Projects",
    .macos => "Documents/Yume Projects",
    else => "Yume Projects",
};

pub fn init(allocator: std.mem.Allocator) !Self {
    const default_project_name = "New Project";
    const home_dir = try utils.getHomeDirectoryOwned(allocator);
    defer allocator.free(home_dir);
    const default_project_path = try std.fs.path.join(allocator, &[_][]const u8{ home_dir, yume_projects_root });
    defer allocator.free(default_project_path);
    var self = Self{
        .allocator = allocator,
        .project_name = try std.ArrayList(u8).initCapacity(allocator, default_project_name.len + 1),
        .project_path = try std.ArrayList(u8).initCapacity(allocator, default_project_path.len + 1),
    };
    self.project_name.appendSliceAssumeCapacity(default_project_name);
    self.project_name.appendAssumeCapacity(0);
    self.project_path.appendSliceAssumeCapacity(default_project_path);
    self.project_path.appendAssumeCapacity(0);
    return self;
}

pub fn deinit(self: *Self) void {
    self.project_name.deinit();
    self.project_path.deinit();
}

pub fn open(self: *Self) void {
    c.ImGui_OpenPopupEx(self.id);
    self.is_open = true;
}

pub fn close(self: *Self) void {
    self.is_open = false;
}

pub fn show(self: *Self, ctx: *GameApp) void {
    if (!self.is_open) return;
    c.ImGui_PushID("new-project-modal");
    defer c.ImGui_PopID();
    const viewport = c.ImGui_GetMainViewport();
    c.ImGui_SetNextWindowPos(viewport.*.Pos, c.ImGuiCond_Always);
    c.ImGui_SetNextWindowSize(viewport.*.Size, c.ImGuiCond_Always);

    const title = "New Project";
    const flags = c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoSavedSettings;
    self.id = c.ImGui_GetID(title);
    if (c.ImGui_Begin(title, &self.is_open, flags)) {
        const avail = c.ImGui_GetContentRegionAvail();
        const box_height = 700;
        var cursor = c.ImGui_GetCursorPos();
        const padding_y = @max(avail.y - box_height, 0) / 2;
        const padding_x = avail.x * 0.1;
        const end_y = cursor.y + box_height;
        const close_btn_size = 32;
        c.ImGui_SetCursorPosX(avail.x - (padding_x + close_btn_size));
        c.ImGui_SetCursorPosY(cursor.y + (padding_y + close_btn_size));
        if (c.ImGui_ImageButton("##close-btn", @intFromPtr(Editor.close_icon_ds), c.ImVec2{ .x = close_btn_size, .y = close_btn_size })) {
            self.close();
        }

        c.ImGui_SetCursorPosY(c.ImGui_GetCursorPosY() + box_height / 4);
        c.ImGui_IndentEx(padding_x);
        c.ImGui_PushFont(Editor.roboto32);
        c.ImGui_Text("Project Name:");
        for (0..1) |_| c.ImGui_Spacing();
        c.ImGui_PopFont();
        var callback = imutils.ArrayListU8ResizeCallback{ .buf = &self.project_name };
        c.ImGui_PushItemWidth(-padding_x);
        c.ImGui_PushFont(Editor.roboto24);
        _ = c.ImGui_InputTextEx(
            "##new_project-project_name",
            self.project_name.items.ptr,
            self.project_name.capacity,
            c.ImGuiInputTextFlags_CallbackResize,
            imutils.ArrayListU8ResizeCallback.InputTextCallback,
            &callback,
        );
        c.ImGui_PopItemWidth();
        c.ImGui_PopFont();

        c.ImGui_PushFont(Editor.roboto32);
        for (0..8) |_| c.ImGui_Spacing();
        c.ImGui_Text("Project Path:");
        for (0..1) |_| c.ImGui_Spacing();
        c.ImGui_PopFont();
        callback = imutils.ArrayListU8ResizeCallback{ .buf = &self.project_path };
        c.ImGui_PushItemWidth(-padding_x);
        c.ImGui_PushFont(Editor.roboto24);
        _ = imutils.inputDirPath(
            "##new_project-project_path",
            Editor.inputs.window,
            self.project_path.items.ptr,
            self.project_path.capacity,
            c.ImGuiInputTextFlags_CallbackResize,
            imutils.ArrayListU8ResizeCallback.InputTextCallback,
            &callback,
            &onPathSelect,
            self,
            false,
        );
        c.ImGui_PopItemWidth();
        c.ImGui_PopFont();

        c.ImGui_BeginDisabled(!self.haveValidParams());
        c.ImGui_PushFont(Editor.roboto32);
        const create_label = "    Create    ";
        const create_label_size = c.ImGui_CalcTextSize(create_label);
        cursor = c.ImGui_GetCursorPos();
        c.ImGui_SetCursorPosX(avail.x - (padding_x + create_label_size.x));
        c.ImGui_SetCursorPosY(end_y);
        if (c.ImGui_Button(create_label)) {
            self.onCreateClick(ctx) catch @panic("failed to create the template project");
        }
        c.ImGui_PopFont();
        for (0..3) |_| c.ImGui_Unindent();
        c.ImGui_EndDisabled();
        c.ImGui_End();
    }
}

fn onCreateClick(self: *Self, ctx: *GameApp) !void {
    const project_name = self.project_name.items[0 .. self.project_name.items.len - 1];
    const fullpath = try std.fs.path.join(self.allocator, &[_][]const u8{
        self.project_path.items[0 .. self.project_path.items.len - 1],
        project_name,
    });
    defer self.allocator.free(fullpath);
    const scene_directory_path = try std.fs.path.join(self.allocator, &[_][]const u8{
        fullpath,
        "scenes",
    });
    defer self.allocator.free(scene_directory_path);
    const projfile = try std.fs.path.join(self.allocator, &[_][]const u8{ fullpath, "yume.json" });
    defer self.allocator.free(projfile);
    const default_scene_file = try std.fs.path.join(self.allocator, &[_][]const u8{ fullpath, "scenes", "Default.scene" });
    defer self.allocator.free(default_scene_file);

    try std.fs.cwd().makePath(scene_directory_path);

    var project = Project{
        .allocator = self.allocator,

        .project_name = project_name,
        .scenes = std.ArrayList(Uuid).init(self.allocator),
        .default_scene = Uuid.new(),

        .resources = std.AutoHashMap(Uuid, Project.Resource).init(self.allocator),

        .resources_index = undefined,
        .resources_builtins = undefined,
    };
    defer project.unload();

    try project.resources.put(
        project.default_scene,
        Project.Resource{
            .id = project.default_scene,
            .path = try self.allocator.dupe(u8, "scenes/Default Scene.scene"),
        },
    );

    var scene = try Scene.init(self.allocator);
    defer scene.deinit();

    {
        const main_camera = scene.newObject(.{
            .name = self.allocator.dupeZ(u8, "Main Camera") catch @panic("OOM"),
            .transform = Mat4.translation(Vec3.make(0, 1, 0)),
        }) catch @panic("OOM");
        defer main_camera.deref();
        main_camera.addComponent(Camera, .{
            .perspective = .{
                .fovy_rad = std.math.degreesToRadians(70.0),
                .far = 200,
                .near = 0.1,
            },
        });
        const apes = scene.newObject(.{
            .name = self.allocator.dupeZ(u8, "Apes Together Strong!") catch @panic("OOM"),
            .transform = Mat4.translation(Vec3.make(0, 3, 0)),
        }) catch @panic("OOM");
        defer apes.deref();
        var monkey = scene.newObject(.{
            .name = self.allocator.dupeZ(u8, "Monkey") catch @panic("OOM"),
            .transform = Mat4.translation(Vec3.make(-5, 3, 0)),
        }) catch @panic("OOM");
        defer monkey.deref();
        monkey.addComponent(MeshRenderer, .{
            .mesh = AssetsDatabase.getOrLoadMesh(try Project.current().?.getResourceId("builtin://u.obj")) catch @panic("Failed to get monkey mesh"),
            .material = AssetsDatabase.getOrLoadMaterial(try Project.current().?.getResourceId("builtin://materials/none.mat.json")) catch @panic("Failed to get none material"),
        });
        apes.addChildren(monkey);

        const empire = scene.newObject(.{
            .name = self.allocator.dupeZ(u8, "Lost Empire") catch @panic("OOM"),
            .transform = Mat4.translation(Vec3.make(5.0, -10.0, 0.0)),
        }) catch @panic("OOM");
        defer empire.deref();
        var empire_material = AssetsDatabase.getOrLoadMaterial(try Project.current().?.getResourceId("builtin://materials/default.mat.json")) catch @panic("Failed to get default mesh material");

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

        const lost_empire_tex_handle = AssetsDatabase.loadTexture(try Project.current().?.getResourceId("builtin://lost_empire-RGBA.png")) catch @panic("Failed to load texture");
        const lost_empire_tex = AssetsDatabase.getTexture(lost_empire_tex_handle) catch @panic("Failed to get empire texture");
        // const lost_empire_tex = (ctx.engine.textures.get("empire_diffuse") orelse @panic("Failed to get empire texture"));

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
            .mesh = AssetsDatabase.getOrLoadMesh(try Project.current().?.getResourceId("builtin://lost_empire.obj")) catch @panic("Failed to get triangle mesh"),
            .material = empire_material,
        });
    }

    const scene_json = try std.json.stringifyAlloc(self.allocator, scene, .{ .whitespace = .indent_4 });
    defer self.allocator.free(scene_json);
    var scene_file = try std.fs.cwd().createFile(default_scene_file, .{});
    defer scene_file.close();
    try scene_file.writeAll(scene_json);

    const json = try std.json.stringifyAlloc(self.allocator, project, .{ .whitespace = .indent_4 });
    defer self.allocator.free(json);
    var file = try std.fs.cwd().createFile(projfile, .{});
    defer file.close();
    try file.writeAll(json);

    try Project.load(self.allocator, projfile);
    try ctx.loadScene(project.default_scene);
    self.close();
}

fn onPathSelect(user_data: ?*anyopaque, paths: [*c]const [*c]const u8, _: c_int) callconv(.C) void {
    var me: *Self = @ptrCast(@alignCast(user_data));
    if (paths == null) {
        std.debug.print("SDL error {s}\n", .{c.SDL_GetError()});
        return;
    }
    if (paths[0] == null) {
        std.debug.print("empty selection\n", .{});
        return;
    }
    me.project_path.clearRetainingCapacity();
    me.project_path.appendSlice(std.mem.span(paths[0])) catch @panic("OOM");
    me.project_path.append(0) catch @panic("OOM");
}

fn haveValidParams(self: *Self) bool {
    return (self.project_name.items.len > 0 and self.project_name.items[0] != 0) and (self.project_path.items.len > 0 and self.project_path.items[0] != 0);
}
