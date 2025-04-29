const c = @import("clibs");

const std = @import("std");

const GameApp = @import("yume").GameApp;

const logs_harness = @import("../logs_harness.zig");
const Log = logs_harness.Log;

const Editor = @import("../Editor.zig");
const EditorDatabase = @import("../EditorDatabase.zig");
const imutils = @import("../imutils.zig");

const Self = @This();

allocator: std.mem.Allocator,

logs: std.ArrayList(Log),

filter_str: imutils.ImString,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .logs = std.ArrayList(Log).init(allocator),

        .filter_str = imutils.ImString.init(allocator) catch @panic("OOM"),
    };
}

pub fn deinit(self: *Self) void {
    self.logs.deinit();
    self.filter_str.deinit();
}

pub fn draw(self: *Self) !void {
    if (c.ImGui_Begin("Logs", null, c.ImGuiWindowFlags_NoCollapse)) {
        logs_harness.drainInto(&self.logs) catch @panic("OOM");

        c.ImGui_BeginGroup();
        {
            const avail = c.ImGui_GetContentRegionAvail();

            if (c.ImGui_Button("Clear")) {
                logs_harness.free(self.logs.items);
                self.logs.clearRetainingCapacity();
            }
            c.ImGui_SameLine();

            var cursor = c.ImGui_GetCursorPos();
            const end_of_left = cursor.x;
            const small_button_width = small_icon_size.x + (c.ImGui_GetStyle().*.FramePadding.x * 2);
            cursor.x = avail.x - (small_button_width * 4);

            const middle_width = cursor.x - end_of_left;
            const filter_width = @min(middle_width, 200);
            const label_width = c.ImGui_CalcTextSize("filter").x;
            c.ImGui_SetCursorPosX(cursor.x - (label_width + filter_width + (c.ImGui_GetStyle().*.FramePadding.x * 4)));
            c.ImGui_Text("filter:");
            c.ImGui_SameLine();

            c.ImGui_PushItemWidth(filter_width);
            _ = c.ImGui_InputTextEx(
                "##filter-input",
                self.filter_str.buf,
                self.filter_str.size(),
                c.ImGuiInputTextFlags_CallbackResize,
                imutils.ImString.InputTextCallback,
                &self.filter_str,
            );
            c.ImGui_PopItemWidth();

            c.ImGui_SetCursorPos(cursor);

            filterToggleButton(
                "error",
                &EditorDatabase.storage().log_filters.err,
                try Editor.getImGuiTexture("editor://icons/error.png"),
                try Editor.getImGuiTexture("editor://icons/error-mono.png"),
            );
            cursor.x = cursor.x + small_button_width;
            c.ImGui_SetCursorPos(cursor);
            filterToggleButton(
                "warning",
                &EditorDatabase.storage().log_filters.warn,
                try Editor.getImGuiTexture("editor://icons/warning.png"),
                try Editor.getImGuiTexture("editor://icons/warning-mono.png"),
            );
            cursor.x = cursor.x + small_button_width;
            c.ImGui_SetCursorPos(cursor);
            filterToggleButton(
                "info",
                &EditorDatabase.storage().log_filters.info,
                try Editor.getImGuiTexture("editor://icons/info.png"),
                try Editor.getImGuiTexture("editor://icons/info-mono.png"),
            );
            cursor.x = cursor.x + small_button_width;
            c.ImGui_SetCursorPos(cursor);
            filterToggleButton(
                "debug",
                &EditorDatabase.storage().log_filters.debug,
                try Editor.getImGuiTexture("editor://icons/debug.png"),
                try Editor.getImGuiTexture("editor://icons/debug-mono.png"),
            );
        }
        c.ImGui_EndGroup();

        c.ImGui_Separator();

        const avail = c.ImGui_GetContentRegionAvail();
        if (c.ImGui_BeginChild("logs", avail, 0, 0)) {
            var i = self.logs.items.len;
            while (i > 0) {
                i -= 1;
                const log = self.logs.items[i];
                if (!self.filter(log)) {
                    continue;
                }
                const icon = switch (log.level) {
                    .err => try Editor.getImGuiTexture("editor://icons/error.png"),
                    .warn => try Editor.getImGuiTexture("editor://icons/warning.png"),
                    .info => try Editor.getImGuiTexture("editor://icons/info.png"),
                    .debug => try Editor.getImGuiTexture("editor://icons/debug.png"),
                };
                c.ImGui_Image(icon, .{ .x = 28, .y = 28 });
                c.ImGui_SameLine();
                c.ImGui_Text(log.message);
            }
        }
        c.ImGui_EndChild();
    }
    c.ImGui_End();
}

inline fn filter(self: Self, log: Log) bool {
    const level_match = switch (log.level) {
        .err => EditorDatabase.storage().log_filters.err,
        .warn => EditorDatabase.storage().log_filters.warn,
        .info => EditorDatabase.storage().log_filters.info,
        .debug => EditorDatabase.storage().log_filters.debug,
    };
    if (!level_match) {
        return false;
    }

    const needle = self.filter_str.span();
    if (needle.len == 0) {
        return true;
    }

    return std.ascii.indexOfIgnoreCase(log.message, needle) != null;
}

fn filterToggleButton(label: [*c]const u8, flag: *bool, enable: c.ImTextureID, disable: c.ImTextureID) void {
    if (c.ImGui_ImageButton(label, if (flag.*) enable else disable, small_icon_size)) {
        flag.* = !flag.*;
    }
}

const small_icon_size = c.ImVec2{ .x = 16, .y = 16 };
