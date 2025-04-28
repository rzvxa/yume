const c = @import("clibs");

const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.NewProjectModal);

const Uuid = @import("yume").Uuid;
const Scene = @import("yume").scene_graph.Scene;

const GameApp = @import("yume").GameApp;
const Engine = @import("yume").VulkanEngine;
const VulkanDeleter = @import("yume").VulkanDeleter;
const check_vk = @import("yume").vki.check_vk;
const Camera = @import("yume").Camera;
const MeshRenderer = @import("yume").MeshRenderer;
const Assets = @import("yume").Assets;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;
const utils = @import("yume").utils;

const imutils = @import("imutils.zig");
const Editor = @import("Editor.zig");
const Project = @import("Project.zig");
const AssetsDatabase = @import("AssetsDatabase.zig");
const EditorDatabase = @import("EditorDatabase.zig");

const Self = @This();

allocator: std.mem.Allocator,

id: c.ImGuiID = undefined,
is_open: bool = false,

project_name: imutils.ImString,
project_path: imutils.ImString,

const yume_projects_root = switch (builtin.os.tag) {
    .windows => "Documents\\Yume Projects",
    .macos => "Documents/Yume Projects",
    else => "Yume Projects",
};

pub fn init(allocator: std.mem.Allocator) !Self {
    const default_project_name = "New Project";
    const home_dir = try utils.getHomeDirectoryOwned(allocator);
    defer allocator.free(home_dir);
    const default_project_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ home_dir, yume_projects_root });
    defer allocator.free(default_project_path);
    return .{
        .allocator = allocator,
        .project_name = try imutils.ImString.fromSlice(allocator, default_project_name),
        .project_path = try imutils.ImString.fromSlice(allocator, default_project_path),
    };
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
        if (c.ImGui_ImageButton("##close-btn", Editor.close_icon_ds, c.ImVec2{ .x = close_btn_size, .y = close_btn_size })) {
            self.close();
        }

        c.ImGui_SetCursorPosY(c.ImGui_GetCursorPosY() + box_height / 4);
        c.ImGui_IndentEx(padding_x);
        c.ImGui_PushFont(Editor.roboto32);
        c.ImGui_Text("Project Name:");
        for (0..1) |_| c.ImGui_Spacing();
        c.ImGui_PopFont();
        c.ImGui_PushItemWidth(-padding_x);
        c.ImGui_PushFont(Editor.roboto24);
        _ = c.ImGui_InputTextEx(
            "##new_project-project_name",
            self.project_name.buf,
            self.project_name.size(),
            c.ImGuiInputTextFlags_CallbackResize,
            &imutils.ImString.InputTextCallback,
            &self.project_name,
        );
        c.ImGui_PopItemWidth();
        c.ImGui_PopFont();

        c.ImGui_PushFont(Editor.roboto32);
        for (0..8) |_| c.ImGui_Spacing();
        c.ImGui_Text("Project Path:");
        for (0..1) |_| c.ImGui_Spacing();
        c.ImGui_PopFont();
        c.ImGui_PushItemWidth(-padding_x);
        c.ImGui_PushFont(Editor.roboto24);
        _ = imutils.inputDirPath(
            "##new_project-project_path",
            ctx.window,
            self.project_path.buf,
            self.project_path.size(),
            c.ImGuiInputTextFlags_CallbackResize,
            imutils.ImString.InputTextCallback,
            &self.project_path,
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
    const project_name = self.project_name.span();
    const project_path = self.project_path.span();
    const fullpath = try std.fs.path.resolve(self.allocator, &[_][]const u8{
        project_path,
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

        .project_name = try self.allocator.dupe(u8, project_name),
        .scenes = std.ArrayList(Uuid).init(self.allocator),
        .default_scene = Uuid.new(),

        .resources = std.AutoHashMap(Uuid, AssetsDatabase.Resource).init(self.allocator),

        .resources_index = undefined,
        .resources_builtins = undefined,
    };
    defer project.unload();

    try project.resources.put(
        project.default_scene,
        AssetsDatabase.Resource{
            .id = project.default_scene,
            .path = try self.allocator.dupe(u8, "scenes/Default.scene"),
        },
    );

    var scene = try Scene.init(self.allocator);
    defer scene.deinit();

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
    EditorDatabase.storage().last_open_scene = project.default_scene;
    self.close();
}

fn onPathSelect(user_data: ?*anyopaque, paths: [*c]const [*c]const u8, _: c_int) callconv(.C) void {
    var me: *Self = @ptrCast(@alignCast(user_data));
    if (paths == null) {
        log.err("SDL error {s}\n", .{c.SDL_GetError()});
        return;
    }
    if (paths[0] == null) {
        log.err("empty selection\n", .{});
        return;
    }
    me.project_path.set(std.mem.span(paths[0])) catch @panic("OOM");
}

fn haveValidParams(self: *Self) bool {
    return self.project_name.length() > 0 and self.project_path.length() > 0;
}
