const c = @import("clibs");
const std = @import("std");

const utils = @import("yume").utils;
const assets = @import("yume").assets;

const Editor = @import("Editor.zig");
const Project = @import("Project.zig");
const ProjectExplorerWindow = @import("windows/ProjectExplorerWindow.zig");

var imutils_context: Context = undefined;

pub fn createContext() void {
    imutils_context = .{
        .imgui_context = c.ImGui_CreateContext(null).?,
    };
}

pub inline fn newFrame() void {
    c.cImGui_ImplVulkan_NewFrame();
    c.cImGui_ImplSDL3_NewFrame();
    c.ImGui_NewFrame();
}

pub inline fn render() void {
    c.ImGui_Render();
}

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

/// Draws a single line of text (provided in `line`) starting at `base_pos`,
/// with the text’s character offset in the full text given by `line_offset`.
/// A wrap_width is used (if nonzero) when calculating the text sizes.
/// Any highlight ranges (provided in `ranges`) that intersect this line will
/// be drawn using the highlight color.
pub fn drawHighlightedTextLine(
    line: []const u8,
    line_offset: usize,
    base_pos: c.ImVec2,
    wrap_width: f32,
    ranges: []const utils.Range,
    font: *c.ImFont,
    font_size: f32,
    highlight_color: c.ImU32,
) void {
    const drawlist = c.ImGui_GetWindowDrawList();

    var range_index: usize = 0;
    while (range_index < ranges.len) : (range_index += 1) {
        const r = ranges[range_index];
        if (r.end <= line_offset or r.start >= line_offset + line.len) continue;

        const rel_start = if (r.start < line_offset) 0 else r.start - line_offset;
        const rel_end = if (r.end > line_offset + line.len) line.len else r.end - line_offset;

        const prefix_width = c.ImGui_CalcTextSizeEx(line[0..rel_start].ptr, line[rel_start..].ptr, false, wrap_width).x;
        const seg_width = c.ImGui_CalcTextSizeEx(line[rel_start..rel_end].ptr, line[rel_end..].ptr, false, wrap_width).x;

        const highlight_min = c.ImVec2{
            .x = base_pos.x + prefix_width,
            .y = base_pos.y,
        };
        const highlight_max = c.ImVec2{
            .x = base_pos.x + prefix_width + seg_width,
            .y = base_pos.y + font_size,
        };

        c.ImDrawList_AddRectFilled(drawlist, highlight_min, highlight_max, highlight_color);
    }

    c.ImDrawList_AddTextImFontPtrEx(
        drawlist,
        font,
        font_size,
        base_pos,
        c.ImGui_GetColorU32(c.ImGuiCol_Text),
        line.ptr,
        line[line.len..].ptr,
        wrap_width,
        null,
    );
}

/// Draws text with highlighted ranges. The full text is provided in `text`.
/// The `ranges` slice contains ranges (as character index intervals) to be highlighted.
pub fn drawTextWithHighlight(
    text: []const u8,
    ranges: []const utils.Range,
    wrap_width: f32,
) void {
    const base_pos = c.ImGui_GetCursorScreenPos();

    const font = c.ImGui_GetFont();
    const font_size = c.ImGui_GetFontSize();
    const style = c.ImGui_GetStyle().*;
    const highlight_color = c.ImGui_GetColorU32ImVec4(style.Colors[c.ImGuiCol_TextSelectedBg]);

    var line_start: usize = 0;
    var cursor = base_pos;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            const line = text[line_start..i];
            drawHighlightedTextLine(line, line_start, cursor, wrap_width, ranges, font, font_size, highlight_color);
            cursor.y += font_size + style.ItemSpacing.y;
            line_start = i + 1;
        }
    }
    c.ImGui_SetCursorScreenPos(cursor);
}

pub fn fourwayInputs() enum { none, up, down, left, right } {
    const ctrl = c.ImGui_IsKeyDown(c.ImGuiKey_ModCtrl);
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_UpArrow) or
        (ctrl and c.ImGui_IsKeyPressed(c.ImGuiKey_K)))
    {
        return .up;
    } else if (c.ImGui_IsKeyPressed(c.ImGuiKey_DownArrow) or
        (ctrl and c.ImGui_IsKeyPressed(c.ImGuiKey_J)))
    {
        return .down;
    } else if (c.ImGui_IsKeyPressed(c.ImGuiKey_LeftArrow) or
        (ctrl and c.ImGui_IsKeyPressed(c.ImGuiKey_H)))
    {
        return .left;
    } else if (c.ImGui_IsKeyPressed(c.ImGuiKey_RightArrow) or
        (ctrl and c.ImGui_IsKeyPressed(c.ImGuiKey_L)))
    {
        return .right;
    } else {
        return .none;
    }
}

pub fn assetHandleInput(label: [*:0]const u8, handle: assets.AssetHandle) !?assets.AssetHandle {
    var urn = handle.uuid.urnZ();
    c.ImGui_PushID(label);
    defer c.ImGui_PopID();
    const id = c.ImGui_GetItemID();
    _ = c.ImGui_InputText("##reference", &urn, 37, c.ImGuiInputTextFlags_ReadOnly);
    c.ImGui_SameLine();
    if (c.ImGui_Button("...")) {
        imutils_context.active_asset_handle_input = id;
        try Project.browseAssets(handle, .{
            .locked_filters = &.{
                ProjectExplorerWindow.filterByResourceType(.obj),
            },
            .callback = Project.OnSelectAsset.callback(Context, &imutils_context, Context.onSelectAsset),
        });
    }
    c.ImGui_SameLine();
    _ = c.ImGui_Text("Mesh");

    if (imutils_context.active_asset_handle_input == id) {
        return imutils_context.new_asset_handle;
    }
    return null;
}

const Context = struct {
    imgui_context: *c.ImGuiContext,
    active_asset_handle_input: c.ImGuiID = 0,
    new_asset_handle: ?assets.AssetHandle = null,

    fn onSelectAsset(ctx: *Context, handle: ?assets.AssetHandle) void {
        ctx.new_asset_handle = handle;
    }
};
