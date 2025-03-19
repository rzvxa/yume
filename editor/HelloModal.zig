const c = @import("clibs");

const builtin = @import("builtin");
const std = @import("std");

const Project = @import("Project.zig");

const imutils = @import("imutils.zig");
const Editor = @import("Editor.zig");
const utils = @import("yume").utils;

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

pub fn show(self: *Self) void {
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

        c.ImGui_SetCursorPosY(c.ImGui_GetCursorPosY() + box_height / 4);
        c.ImGui_PushFont(Editor.roboto32);
        c.ImGui_Text("Hello!");
        for (0..1) |_| c.ImGui_Spacing();
        if (c.ImGui_Button("New Project")) {
            Editor.instance().newProject();
        }
        c.ImGui_SameLine();
        if (c.ImGui_Button("Open Project")) {
            Editor.instance().openProject();
        }
        c.ImGui_Text("Recent:");
        c.ImGui_PopFont();
        c.ImGui_EndGroup();

        c.ImGui_End();
    }
}
