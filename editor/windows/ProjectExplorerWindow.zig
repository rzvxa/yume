const c = @import("clibs");

const std = @import("std");

const Editor = @import("../Editor.zig");

const Self = @This();

project_explorer_path: []const u8 = "",

pub fn draw(_: *Self) void {
    if (c.ImGui_Begin("Project", null, 0)) {
        const item_sz = 64;
        const bread_crumb_height = c.ImGui_GetFrameHeight() + (2 * c.ImGui_GetStyle().*.FramePadding.y);
        const col_count = @max(1, c.ImGui_GetContentRegionAvail().x / (item_sz + 32));
        const avail = c.ImGui_GetContentRegionAvail();
        const grid_size = c.ImVec2{ .x = avail.x, .y = avail.y - bread_crumb_height };
        if (c.ImGui_BeginChildFrameEx(c.ImGui_GetID("files grid"), grid_size, c.ImGuiWindowFlags_NoBackground)) {
            c.ImGui_ColumnsEx(@intFromFloat(col_count), "dir", false);
            const ItemDrawer = struct {
                fn draw(icon: c.ImTextureID, name: []const u8) void {
                    c.ImGui_Spacing();
                    c.ImGui_Spacing();
                    c.ImGui_Spacing();
                    c.ImGui_PushID(name.ptr);
                    const text_size = c.ImGui_CalcTextSize(name.ptr);
                    const btn_size = c.ImVec2{
                        .x = @max(item_sz, text_size.x) + (2 * c.ImGui_GetStyle().*.FramePadding.x),
                        .y = item_sz + text_size.y + (2 * c.ImGui_GetStyle().*.FramePadding.y),
                    };
                    const cursor = c.ImGui_GetCursorPos();
                    _ = c.ImGui_ButtonEx("##name", btn_size);
                    c.ImGui_SetCursorPos(cursor);
                    c.ImGui_SetCursorPosX(cursor.x + ((btn_size.x - item_sz) / 2));
                    _ = c.ImGui_Image(icon, c.ImVec2{ .x = item_sz, .y = item_sz });
                    c.ImGui_SetCursorPosX(cursor.x + ((btn_size.x - text_size.x) / 2));
                    _ = c.ImGui_Text(name.ptr);
                    c.ImGui_PopID();
                    c.ImGui_Spacing();
                    c.ImGui_Spacing();
                    c.ImGui_Spacing();
                }
            };
            for (0..10) |i| {
                const is_dir = i < 3;
                const icon = if (is_dir) Editor.folder_icon_ds else Editor.file_icon_ds;
                var name = std.mem.zeroes([256]u8);

                if (is_dir) {
                    _ = std.fmt.bufPrintZ(&name, "New Folder ({d})", .{i + 1}) catch @panic("buf overflow");
                } else {
                    _ = std.fmt.bufPrintZ(&name, "Script-{d}.lua", .{i + 1}) catch @panic("buf overflow");
                }
                ItemDrawer.draw(icon, &name);
                c.ImGui_NextColumn();
            }
            c.ImGui_EndChildFrame();
        }
        const crumbs = [3][]const u8{ "Project", "Directory one", "Dir2" };
        for (crumbs) |crumb| {
            _ = c.ImGui_Button(crumb.ptr);
            c.ImGui_SameLineEx(0, 0);
            c.ImGui_BeginDisabled(true);
            _ = c.ImGui_ArrowButton("sep", c.ImGuiDir_Right);
            c.ImGui_EndDisabled();
            c.ImGui_SameLineEx(0, 0);
        }

        _ = c.ImGui_Text("[You are here]");
    }
    c.ImGui_End();
}
