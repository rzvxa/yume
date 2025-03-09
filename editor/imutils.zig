const c = @import("clibs");
const std = @import("std");

const Editor = @import("Editor.zig");

pub const ArrayListU8ResizeCallback = struct {
    buf: *std.ArrayList(u8),
    pub fn InputTextCallback(data: [*c]c.ImGuiInputTextCallbackData) callconv(.C) c_int {
        const user_data = @as(*@This(), @ptrCast(@alignCast(data.*.UserData)));
        if (data.*.EventFlag == c.ImGuiInputTextFlags_CallbackResize) {
            // Resize string callback
            // If for some reason we refuse the new length (BufTextLen) and/or capacity (BufSize) we need to set them back to what we want.
            // std::string* str = user_data->Str;
            std.debug.assert(data.*.Buf == user_data.buf.items.ptr);
            user_data.buf.resize(@intCast(data.*.BufTextLen)) catch @panic("OOM");
            data.*.Buf = user_data.buf.items.ptr;
        }
        return 0;
    }
};

pub fn inputFilePath(
    label: [*c]const u8,
    path_buf: [*c]u8,
    buf_size: usize,
    flags: c.ImGuiInputTextFlags,
    callback: c.ImGuiInputTextCallback,
    user_data: ?*anyopaque,
) bool {
    c.ImGui_PushID(label);
    defer c.ImGui_PopID();
    const browseButtonSize = c.ImGui_GetFontSize();
    c.ImGui_PushItemWidth(c.ImGui_CalcItemWidth() - (browseButtonSize + (4 * c.ImGui_GetStyle().*.FramePadding.x)));
    const changed = c.ImGui_InputTextEx(label, path_buf, buf_size, flags | c.ImGuiInputTextFlags_ReadOnly, callback, user_data);
    c.ImGui_SameLine();
    if (c.ImGui_ImageButton("browse", @intFromPtr(Editor.browse_icon_ds), c.ImVec2{ .x = browseButtonSize, .y = browseButtonSize })) {}
    c.ImGui_PopItemWidth();

    return changed;
}
