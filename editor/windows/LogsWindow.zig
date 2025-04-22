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

filter_buf: std.ArrayList(u8),

pub fn init(ctx: *GameApp) Self {
    var self = Self{
        .allocator = ctx.allocator,

        .logs = std.ArrayList(Log).init(ctx.allocator),

        .filter_buf = std.ArrayList(u8).init(ctx.allocator),
    };
    self.filter_buf.append(0) catch @panic("OOM");
    return self;
}

pub fn deinit(self: *Self) void {
    self.logs.deinit();
    self.filter_buf.deinit();
}

pub fn draw(self: *Self) void {
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

            var callback = imutils.ArrayListU8ResizeCallback{ .buf = &self.filter_buf };
            c.ImGui_PushItemWidth(filter_width);
            _ = c.ImGui_InputTextEx(
                "##filter-input",
                self.filter_buf.items.ptr,
                self.filter_buf.capacity,
                c.ImGuiInputTextFlags_CallbackResize,
                imutils.ArrayListU8ResizeCallback.InputTextCallback,
                &callback,
            );
            c.ImGui_PopItemWidth();

            c.ImGui_SetCursorPos(cursor);

            filterToggleButton("error", &EditorDatabase.storage().log_filters.err, Editor.error_icon_ds, Editor.error_mono_icon_ds);
            cursor.x = cursor.x + small_button_width;
            c.ImGui_SetCursorPos(cursor);
            filterToggleButton("warning", &EditorDatabase.storage().log_filters.warn, Editor.warning_icon_ds, Editor.warning_mono_icon_ds);
            cursor.x = cursor.x + small_button_width;
            c.ImGui_SetCursorPos(cursor);
            filterToggleButton("info", &EditorDatabase.storage().log_filters.info, Editor.info_icon_ds, Editor.info_mono_icon_ds);
            cursor.x = cursor.x + small_button_width;
            c.ImGui_SetCursorPos(cursor);
            filterToggleButton("debug", &EditorDatabase.storage().log_filters.debug, Editor.debug_icon_ds, Editor.debug_mono_icon_ds);
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
                    .err => Editor.error_icon_ds,
                    .warn => Editor.warning_icon_ds,
                    .info => Editor.info_icon_ds,
                    .debug => Editor.debug_icon_ds,
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

    const needle = std.mem.span(@as([*:0]const u8, @ptrCast(self.filter_buf.items.ptr)));
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
