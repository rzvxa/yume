const c = @import("clibs");

const std = @import("std");

const GameApp = @import("yume").GameApp;
const collections = @import("yume").collections;

const logs_harness = @import("../logs_harness.zig");
const Log = logs_harness.Log;

const Editor = @import("../Editor.zig");
const EditorDatabase = @import("../EditorDatabase.zig");
const imutils = @import("../imutils.zig");

const Self = @This();

allocator: std.mem.Allocator,

logs: std.ArrayList(Log),
scopes: collections.StringSentinelArrayHashMap(0, void),

filter_str: imutils.ImString,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,

        .logs = std.ArrayList(Log).init(allocator),
        .scopes = collections.StringSentinelArrayHashMap(0, void).init(allocator),

        .filter_str = imutils.ImString.init(allocator) catch @panic("OOM"),
    };
}

pub fn deinit(self: *Self) void {
    self.logs.deinit();
    self.scopes.deinit();
    self.filter_str.deinit();
}

pub fn draw(self: *Self) !void {
    if (c.ImGui_Begin("Logs", null, c.ImGuiWindowFlags_NoCollapse)) {
        var edstore = &EditorDatabase.storage().logs;
        const new_logs = logs_harness.drainInto(&self.logs) catch @panic("OOM");
        for (self.logs.items[self.logs.items.len - new_logs ..]) |log| {
            try self.scopes.put(log.scope, {});
        }

        self
            .scopes
            .sort(collections.ArrayHashMapStringSentinelSortContext(0){ .keys = self.scopes.keys() });

        c.ImGui_BeginGroup();
        {
            const avail = c.ImGui_GetContentRegionAvail();

            if (c.ImGui_Button("Clear")) {
                logs_harness.free(self.logs.items);
                self.logs.clearAndFree();
                self.scopes.clearRetainingCapacity();
                edstore.scopes.clearRetainingCapacity();
            }
            c.ImGui_SameLine();
            {
                const buf_len = 32;
                const text_width = c.ImGui_CalcTextSize("0" ** buf_len ++ .{0}).x;
                c.ImGui_SetNextItemWidth(text_width);
                var preview_buf: [buf_len]u8 = undefined;
                const preview = prv: {
                    var preview_stream = std.io.fixedBufferStream(&preview_buf);
                    var preview_writer = preview_stream.writer();
                    preview_writer.print("scopes: ", .{}) catch {};
                    const initial_pos = preview_stream.getPos() catch {};
                    var first = true;
                    for (edstore.scopes.keys()) |selected| {
                        if (first) {
                            first = false;
                        } else {
                            preview_writer.print(", ", .{}) catch {};
                        }
                        if (self.scopes.contains(selected)) {
                            preview_writer.print("{s}", .{selected}) catch {};
                        }
                    }

                    if (edstore.scopes.count() == self.scopes.count()) {
                        preview_stream.seekTo(initial_pos) catch {};
                        if (self.scopes.count() == 0) {
                            preview_writer.print("Empty", .{}) catch {};
                        } else {
                            preview_writer.print("All", .{}) catch {};
                        }
                    } else if (edstore.scopes.count() == 0) {
                        preview_stream.seekTo(initial_pos) catch {};
                        preview_writer.print("None", .{}) catch {};
                    }

                    const slice = preview_stream.getWritten();
                    if (slice.len < preview_buf.len) {
                        preview_buf[slice.len] = 0;
                        break :prv preview_buf[0..slice.len :0];
                    } else {
                        preview_buf[slice.len - 1] = 0;
                        preview_buf[slice.len - 2] = '.';
                        preview_buf[slice.len - 3] = '.';
                        preview_buf[slice.len - 4] = '.';
                        break :prv preview_buf[0 .. slice.len - 1 :0];
                    }
                };
                if (c.ImGui_BeginCombo("##scopes", preview, c.ImGuiComboFlags_None)) {
                    defer c.ImGui_EndCombo();
                    c.ImGui_PushItemFlag(c.ImGuiItemFlags_AutoClosePopups, false);
                    defer c.ImGui_PopItemFlag();
                    for (self.scopes.keys()) |scope| {
                        var selected = edstore.scopes.contains(scope);
                        if (c.ImGui_SelectableBoolPtr(scope, &selected, c.ImGuiSelectableFlags_None)) {
                            if (selected) {
                                try edstore.scopes.put(scope, {});
                            } else {
                                _ = edstore.scopes.orderedRemove(scope);
                            }
                        }
                    }
                }
                c.ImGui_SameLine();
            }

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
                &edstore.filters.err,
                try Editor.getImGuiTexture("editor://icons/error.png"),
                try Editor.getImGuiTexture("editor://icons/error-mono.png"),
            );
            cursor.x = cursor.x + small_button_width;
            c.ImGui_SetCursorPos(cursor);
            filterToggleButton(
                "warning",
                &edstore.filters.warn,
                try Editor.getImGuiTexture("editor://icons/warning.png"),
                try Editor.getImGuiTexture("editor://icons/warning-mono.png"),
            );
            cursor.x = cursor.x + small_button_width;
            c.ImGui_SetCursorPos(cursor);
            filterToggleButton(
                "info",
                &edstore.filters.info,
                try Editor.getImGuiTexture("editor://icons/info.png"),
                try Editor.getImGuiTexture("editor://icons/info-mono.png"),
            );
            cursor.x = cursor.x + small_button_width;
            c.ImGui_SetCursorPos(cursor);
            filterToggleButton(
                "debug",
                &edstore.filters.debug,
                try Editor.getImGuiTexture("editor://icons/debug.png"),
                try Editor.getImGuiTexture("editor://icons/debug-mono.png"),
            );
        }
        c.ImGui_EndGroup();

        c.ImGui_Separator();

        const avail = c.ImGui_GetContentRegionAvail();
        if (c.ImGui_BeginChild("logs", avail, 0, 0)) {
            const total_entries: c_int = @intCast(self.logs.items.len);
            const log_entry_height: f32 = 28;
            var clipper = c.ImGuiListClipper{};
            c.ImGuiListClipper_Begin(&clipper, total_entries, log_entry_height);
            while (c.ImGuiListClipper_Step(&clipper)) {
                var idx = clipper.DisplayStart;
                while (idx < clipper.DisplayEnd) : (idx += 1) {
                    const log_index: usize = @intCast((total_entries - 1) - idx);
                    const log = self.logs.items[log_index];
                    if (!edstore.scopes.contains(log.scope) or !self.filter(log)) {
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
            c.ImGuiListClipper_End(&clipper);
        }
        c.ImGui_EndChild();
    }
    c.ImGui_End();
}

inline fn filter(self: Self, log: Log) bool {
    const level_match = switch (log.level) {
        .err => EditorDatabase.storage().logs.filters.err,
        .warn => EditorDatabase.storage().logs.filters.warn,
        .info => EditorDatabase.storage().logs.filters.info,
        .debug => EditorDatabase.storage().logs.filters.debug,
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
