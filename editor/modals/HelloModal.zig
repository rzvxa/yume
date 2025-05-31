const c = @import("clibs");

const builtin = @import("builtin");
const std = @import("std");

const utils = @import("yume").utils;

const Project = @import("../Project.zig");

const imutils = @import("../imutils.zig");
const Editor = @import("../Editor.zig");

const Self = @This();

id: c.ImGuiID = undefined,
is_open: bool = false,

const yume_projects_root = switch (builtin.os.tag) {
    .windows => "Documents\\Yume Projects",
    .macos => "Documents/Yume Projects",
    else => "Yume Projects",
};

pub fn init() !Self {
    return Self{};
}

pub fn deinit(_: *Self) void {}

pub fn open(self: *Self) void {
    c.ImGui_OpenPopupEx(self.id);
    self.is_open = true;
}

pub fn close(self: *Self) void {
    self.is_open = false;
}

pub fn draw(self: *Self) void {
    if (Project.current() != null) return;
    c.ImGui_PushID("hello-modal");
    defer c.ImGui_PopID();
    const viewport = c.ImGui_GetMainViewport();
    c.ImGui_SetNextWindowPos(viewport.*.Pos, c.ImGuiCond_Always);
    c.ImGui_SetNextWindowSize(viewport.*.Size, c.ImGuiCond_Always);

    const title = "Hello";
    const flags = c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoSavedSettings;
    self.id = c.ImGui_GetID(title);
    if (c.ImGui_Begin(title, &self.is_open, flags)) {
        const box_height = 700;

        imutils.alignHorizontal(700, 0.5);
        c.ImGui_BeginGroup();
        defer c.ImGui_EndGroup();

        c.ImGui_SetCursorPosY(c.ImGui_GetCursorPosY() + box_height / 4);
        imutils.alignHorizontal(700, 0.5);
        c.ImGui_Image(Editor.yume_logo_ds, c.ImVec2{ .x = 246, .y = 326 });
        c.ImGui_PushFont(Editor.ubuntu32);
        defer c.ImGui_PopFont();
        c.ImGui_NewLine();
        imutils.alignHorizontal(730, 0.5);
        const version = @import("yume").version;
        c.ImGui_Text("Welcome to Yume v%d.%d.%d", version.major, version.minor, version.patch);
        for (0..1) |_| c.ImGui_Spacing();
        c.ImGui_PushFont(Editor.ubuntu24);
        defer c.ImGui_PopFont();
        imutils.alignHorizontal(875, 0.5);
        if (c.ImGui_Button("\t\tNew Project\t\t")) {
            Editor.instance().newProject();
        }
        c.ImGui_SameLine();
        if (c.ImGui_Button("\t\tOpen Project\t\t")) {
            Editor.instance().openProject();
        }
        c.ImGui_NewLine();
        imutils.alignHorizontal(550, 0.5);
        c.ImGui_Text("Recent:");
    }
    c.ImGui_End();
}
