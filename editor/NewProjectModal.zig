const c = @import("clibs");

const std = @import("std");

const imutils = @import("imutils.zig");
const Editor = @import("Editor.zig");

const Self = @This();

allocator: std.mem.Allocator,

id: c.ImGuiID = undefined,
is_open: bool = true,

project_name: std.ArrayList(u8),
project_path: std.ArrayList(u8),

pub fn init(allocator: std.mem.Allocator) Self {
    var self = Self{
        .allocator = allocator,
        .project_name = std.ArrayList(u8).initCapacity(allocator, 1) catch @panic("OOM"),
        .project_path = std.ArrayList(u8).initCapacity(allocator, 1) catch @panic("OOM"),
    };
    self.project_name.appendAssumeCapacity(0);
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

pub fn show(self: *Self) void {
    if (!self.is_open) return;
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
        _ = imutils.inputFilePath(
            "##new_project-project_path",
            self.project_path.items.ptr,
            self.project_path.capacity,
            c.ImGuiInputTextFlags_CallbackResize,
            imutils.ArrayListU8ResizeCallback.InputTextCallback,
            &callback,
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
        _ = c.ImGui_Button(create_label);
        c.ImGui_PopFont();
        for (0..3) |_| c.ImGui_Unindent();
        c.ImGui_EndDisabled();
        c.ImGui_End();
    }
}

pub fn haveValidParams(self: *Self) bool {
    return (self.project_name.items.len > 0 and self.project_name.items[0] != 0) and (self.project_path.items.len > 0 and self.project_path.items[0] != 0);
}
