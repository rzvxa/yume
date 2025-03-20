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

project_path: std.ArrayList(u8),

const yume_projects_root = switch (builtin.os.tag) {
    .windows => "Documents\\Yume Projects",
    .macos => "Documents/Yume Projects",
    else => "Yume Projects",
};

pub fn init(allocator: std.mem.Allocator) !Self {
    const home_dir = try utils.getHomeDirectoryOwned(allocator);
    defer allocator.free(home_dir);
    const default_project_path = try std.fs.path.join(allocator, &[_][]const u8{ home_dir, yume_projects_root });
    defer allocator.free(default_project_path);
    var self = Self{
        .allocator = allocator,
        .project_path = try std.ArrayList(u8).initCapacity(allocator, default_project_path.len + 1),
    };
    self.project_path.appendSliceAssumeCapacity(default_project_path);
    self.project_path.appendAssumeCapacity(0);
    return self;
}

pub fn deinit(self: *Self) void {
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
        for (0..8) |_| c.ImGui_Spacing();
        c.ImGui_Text("Project Path:");
        for (0..1) |_| c.ImGui_Spacing();
        c.ImGui_PopFont();
        var callback = imutils.ArrayListU8ResizeCallback{ .buf = &self.project_path };
        c.ImGui_PushItemWidth(-padding_x);
        c.ImGui_PushFont(Editor.roboto24);
        _ = imutils.inputFilePath(
            "##open_project-project_path",
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
        const open_label = "    Open    ";
        const open_label_size = c.ImGui_CalcTextSize(open_label);
        cursor = c.ImGui_GetCursorPos();
        c.ImGui_SetCursorPosX(avail.x - (padding_x + open_label_size.x));
        c.ImGui_SetCursorPosY(end_y);
        if (c.ImGui_Button(open_label)) {
            Project.load(self.allocator, self.project_path.items[0 .. self.project_path.items.len - 1]) catch @panic("Failed to load project");
            ctx.loadScene(Project.current().?.default_scene) catch @panic("Failed to load the default scene");
            self.close();
        }
        c.ImGui_PopFont();
        for (0..3) |_| c.ImGui_Unindent();
        c.ImGui_EndDisabled();
        c.ImGui_End();
    }
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
    return self.project_path.items.len > 0 and self.project_path.items[0] != 0;
}
