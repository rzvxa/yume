const c = @import("clibs");
const std = @import("std");

const utils = @import("yume").utils;
const Editor = @import("Editor.zig");

pub const ImString = struct {
    allocator: std.mem.Allocator,
    buf: [*:0]u8,
    cap: usize,

    pub fn init(allocator: std.mem.Allocator) !ImString {
        const str = .{
            .allocator = allocator,
            .buf = try allocator.allocSentinel(u8, 0, 0),
            .cap = 0,
        };
        return str;
    }

    pub fn fromSlice(allocator: std.mem.Allocator, s: [:0]const u8) !ImString {
        return .{
            .allocator = allocator,
            .buf = (try allocator.dupeZ(u8, s)).ptr,
            .cap = s.len,
        };
    }

    pub fn deinit(self: ImString) void {
        self.allocator.free(self.buf[0..self.size()]);
    }

    pub inline fn span(self: *const ImString) [:0]const u8 {
        return std.mem.span(self.buf);
    }

    pub inline fn size(self: *const ImString) usize {
        return self.cap + 1;
    }

    pub inline fn length(self: *const ImString) usize {
        return self.span().len;
    }

    pub fn set(self: *ImString, s: []const u8) !void {
        try self.ensureCapacity(s.len);
        @memcpy(self.buf[0..s.len], s);
        self.buf[s.len] = 0;
    }

    pub fn ensureCapacity(self: *ImString, cap: usize) !void {
        self.buf = @ptrCast(try self.allocator.realloc(self.buf[0..self.size()], cap + 1));
        self.cap = cap;
    }

    pub fn InputTextCallback(data: [*c]c.ImGuiInputTextCallbackData) callconv(.C) c_int {
        const user_data = @as(*@This(), @ptrCast(@alignCast(data.*.UserData)));
        if (data.*.EventFlag == c.ImGuiInputTextFlags_CallbackResize) {
            // Resize string callback
            // If for some reason we refuse the new length (BufTextLen) and/or capacity (BufSize) we need to set them back to what we want.
            std.debug.assert(data.*.Buf == user_data.buf);
            user_data.ensureCapacity(@intCast(data.*.BufSize)) catch @panic("OOM");
            data.*.Buf = user_data.buf;
        }
        return 0;
    }
};

pub fn inputFilePath(
    label: [*c]const u8,
    window: *c.SDL_Window,
    path_buf: [*c]u8,
    buf_size: usize,
    flags: c.ImGuiInputTextFlags,
    text_callback: c.ImGuiInputTextCallback,
    text_user_data: ?*anyopaque,
    fs_callback: c.SDL_DialogFileCallback,
    fs_user_data: ?*anyopaque,
    allow_many: bool,
) bool {
    c.ImGui_PushID(label);
    defer c.ImGui_PopID();
    const browseButtonSize = c.ImGui_GetFontSize();
    c.ImGui_PushItemWidth(c.ImGui_CalcItemWidth() - (browseButtonSize + (4 * c.ImGui_GetStyle().*.FramePadding.x)));
    c.ImGui_BeginDisabled(true);
    const changed = c.ImGui_InputTextEx(label, path_buf, buf_size, flags | c.ImGuiInputTextFlags_ReadOnly, text_callback, text_user_data);
    c.ImGui_EndDisabled();
    c.ImGui_SameLine();
    if (c.ImGui_ImageButton(
        "browse",
        Editor.getImGuiTexture("editor://icons/browse.png") catch @panic("Failed to load browse icon"),
        c.ImVec2{ .x = browseButtonSize, .y = browseButtonSize },
    )) {
        const filters = [_]c.SDL_DialogFileFilter{.{
            .name = "Yume Project File",
            .pattern = "json",
        }};
        c.SDL_ShowOpenFileDialog(fs_callback, fs_user_data, window, &filters, filters.len, path_buf, allow_many);
    }
    c.ImGui_PopItemWidth();

    return changed;
}

pub fn inputDirPath(
    label: [*c]const u8,
    window: *c.SDL_Window,
    path_buf: [*c]u8,
    buf_size: usize,
    flags: c.ImGuiInputTextFlags,
    text_callback: c.ImGuiInputTextCallback,
    text_user_data: ?*anyopaque,
    fs_callback: c.SDL_DialogFileCallback,
    fs_user_data: ?*anyopaque,
    allow_many: bool,
) bool {
    c.ImGui_PushID(label);
    defer c.ImGui_PopID();
    const browseButtonSize = c.ImGui_GetFontSize();
    c.ImGui_PushItemWidth(c.ImGui_CalcItemWidth() - (browseButtonSize + (4 * c.ImGui_GetStyle().*.FramePadding.x)));
    c.ImGui_BeginDisabled(true);
    const changed = c.ImGui_InputTextEx(label, path_buf, buf_size, flags | c.ImGuiInputTextFlags_ReadOnly, text_callback, text_user_data);
    c.ImGui_EndDisabled();
    c.ImGui_SameLine();
    if (c.ImGui_ImageButton(
        "browse",
        Editor.getImGuiTexture("editor://icons/browse.png") catch @panic("Failed to load browse icon"),
        c.ImVec2{ .x = browseButtonSize, .y = browseButtonSize },
    )) {
        c.SDL_ShowOpenFolderDialog(fs_callback, fs_user_data, window, path_buf, allow_many);
    }
    c.ImGui_PopItemWidth();

    return changed;
}

pub fn alignHorizontal(item_width: f32, alignment: f32) void {
    const avail = c.ImGui_GetContentRegionAvail().x;

    const off = (avail - item_width) * alignment;
    if (off > 0.0) {
        c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + off);
    }
}

pub fn buttonCenteredOnLine(label: [*c]const u8, alignment: f32) bool {
    const style = c.ImGui_GetStyle();
    const size = c.ImGui_CalcTextSize(label).x + style.*.FramePadding.x * 2.0;
    alignHorizontal(size, alignment);
    return c.ImGui_Button(label);
}

pub fn collapsingHeaderWithCheckBox(label: [*c]const u8, checked: [*c]bool, flags: c.ImGuiTreeNodeFlags) bool {
    c.ImGui_PushID(label);
    defer c.ImGui_PopID();
    if (checked != null) {
        _ = c.ImGui_Checkbox("###enable", checked);
        const x = c.ImGui_GetCursorPosX();
        const style = c.ImGui_GetStyle();
        c.ImGui_SameLineEx(x + c.ImGui_GetFrameHeight() + style.*.ItemInnerSpacing.x - 1, 0);
    }
    return c.ImGui_CollapsingHeader(label, flags);
}

pub fn helpMessage(message: [*:0]const u8) void {
    c.ImGui_TextDisabled("(?)");
    if (c.ImGui_BeginItemTooltip()) {
        c.ImGui_PushTextWrapPos(c.ImGui_GetFontSize() * 35);
        c.ImGui_TextUnformatted(message);
        c.ImGui_PopTextWrapPos();
        c.ImGui_EndTooltip();
    }
}

pub fn DelayedInputTextEx(
    label: [*c]const u8,
    buf: [*c]u8,
    buf_size: usize,
    flags: c.ImGuiInputTextFlags,
    callback: c.ImGuiInputTextCallback,
    user_data: ?*anyopaque,
) bool {
    const changed = c.ImGui_InputTextEx(label, buf, buf_size, flags, callback, user_data);
    if (c.ImGui_IsItemDeactivated()) {
        return changed;
    }
    return false;
}
