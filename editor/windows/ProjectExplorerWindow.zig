const c = @import("clibs");

const std = @import("std");

const utils = @import("yume").utils;

const Editor = @import("../Editor.zig");
const Project = @import("../Project.zig");
const AssetsDatabase = @import("../AssetsDatabase.zig");
const ResourceNode = @import("../AssetsDatabase.zig").ResourceNode;

const Self = @This();

allocator: std.mem.Allocator,
project_explorer_path: [:0]const u8,
selected_file: ?[:0]const u8 = null,
sort_by_name: bool = true,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{ .allocator = allocator, .project_explorer_path = try allocator.dupeZ(u8, "/assets") };
}

pub fn deinit(self: *Self) void {
    if (self.selected_file) |it| {
        self.allocator.free(it);
    }
    self.allocator.free(self.project_explorer_path);
}

pub const ItemResult = enum {
    none,
    click,
    double_click,
};

pub const OrderedItem = struct {
    key: []const u8,
    res: *ResourceNode,

    pub fn compare(_: void, a: OrderedItem, b: OrderedItem) bool {
        const a_is_dir = a.res.node == .directory;
        const b_is_dir = b.res.node == .directory;
        if (a_is_dir and !b_is_dir) return true;
        if (!a_is_dir and b_is_dir) return false;
        return std.mem.order(u8, a.key, b.key).compare(.lt);
    }
};

pub fn draw(self: *Self) !void {
    var sfa_heap = std.heap.stackFallback(2048, self.allocator);
    const allocator = sfa_heap.get();
    const window_open = c.ImGui_Begin("Project", null, c.ImGuiWindowFlags_NoCollapse);
    const window_active = c.ImGui_IsWindowFocused(0);
    defer c.ImGui_End();
    if (!window_open) return;
    if (Project.current() == null) {
        c.ImGui_Text("No Loaded Project!");
        return;
    }
    const is_root = std.mem.eql(u8, self.project_explorer_path, "/");
    const item_sz: f32 = 64;
    const style = c.ImGui_GetStyle().*;
    const bread_crumb_height = c.ImGui_GetFrameHeight() + (2 * style.FramePadding.y);
    const avail = c.ImGui_GetContentRegionAvail();
    const col_count = @max(1, avail.x / (item_sz + 32));
    const grid_size = c.ImVec2{ .x = avail.x, .y = avail.y - bread_crumb_height };

    const resource_node = (try AssetsDatabase.findResourceNode(self.project_explorer_path)) orelse {
        try self.setProjectExplorerPath("/assets");
        return;
    };

    var items = std.ArrayList(OrderedItem).init(self.allocator);
    defer items.deinit();
    var it = resource_node.children.iterator();
    while (it.next()) |entry| {
        try items.append(OrderedItem{
            .key = entry.key_ptr.*,
            .res = entry.value_ptr,
        });
    }
    if (self.sort_by_name) {
        std.mem.sort(OrderedItem, items.items, {}, OrderedItem.compare);
    }

    const draw_frame = c.ImGui_BeginChildFrameEx(c.ImGui_GetID("files grid"), grid_size, c.ImGuiWindowFlags_NoBackground);
    defer c.ImGui_EndChildFrame();
    if (draw_frame) {
        const table_flags = c.ImGuiTableFlags_SizingStretchSame;
        const draw_table = c.ImGui_BeginTableEx("node", @intFromFloat(col_count), table_flags, grid_size, 0);
        defer c.ImGui_EndTable();
        if (draw_table) {
            var index: usize = 0;
            for (items.items) |item| {
                if (index % @as(usize, @intFromFloat(col_count)) == 0) {
                    c.ImGui_TableNextRow();
                }
                _ = c.ImGui_TableNextColumn();
                const is_dir = item.res.node == .directory;
                const icon =
                    try Editor.getImGuiTexture(
                    blk: {
                        if (is_root) {
                            if (std.mem.eql(u8, item.key, "builtin")) {
                                break :blk "editor://icons/yume.png";
                            } else if (std.mem.eql(u8, item.key, "assets")) {
                                break :blk "editor://icons/library.png";
                            } else if (std.mem.eql(u8, item.key, "editor")) {
                                break :blk "editor://icons/editor.png";
                            } else {
                                break :blk "editor://icons/folder.png";
                            }
                        } else if (is_dir) {
                            break :blk "editor://icons/folder.png";
                        } else {
                            break :blk "editor://icons/file.png";
                        }
                    },
                );

                const result = try drawItem(allocator, icon, item.key, item_sz, style, self.selected_file, window_active);
                if (result == .click) {
                    try self.setSelected(item);
                } else if (result == .double_click) {
                    switch (item.res.node) {
                        .resource => |r| {
                            try utils.tryOpenWithOsDefaultApplication(self.allocator, try AssetsDatabase.getResourcePath(r.id));
                        },
                        .directory => |d| try self.setProjectExplorerPath(d),
                    }
                    std.log.debug("double click {s}", .{item.res.node.path()});
                }
                index += 1;
            }
        }
    }

    const home_height = c.ImGui_GetTextLineHeight();
    if (c.ImGui_ImageButton("/", try Editor.getImGuiTexture("editor://icons/home.png"), .{ .x = home_height, .y = home_height })) {
        try self.setProjectExplorerPath("/");
    }
    c.ImGui_SameLineEx(0, 0);
    const project_explorer_path = try allocator.dupe(u8, self.project_explorer_path);
    defer allocator.free(project_explorer_path);
    var crumbs = try std.fs.path.componentIterator(project_explorer_path);
    var i: c_int = 0;
    while (crumbs.next()) |crumb| : (i += 1) {
        c.ImGui_PushIDInt(i);
        defer c.ImGui_PopID();
        const name = try allocator.dupeZ(u8, crumb.name);
        defer allocator.free(name);
        if (c.ImGui_Button(name)) {
            try self.setProjectExplorerPath(crumb.path);
        }
        c.ImGui_SameLineEx(0, 0);
        c.ImGui_BeginDisabled(true);
        if (i == 0) {
            _ = c.ImGui_Button("://");
        } else {
            _ = c.ImGui_ArrowButton("sep", c.ImGuiDir_Right);
        }
        c.ImGui_EndDisabled();
        c.ImGui_SameLineEx(0, 0);
    }
}

fn drawItem(
    allocator: std.mem.Allocator,
    icon: c.ImTextureID,
    key: []const u8,
    item_sz: f32,
    style: c.ImGuiStyle,
    selected_file: ?[]const u8,
    active: bool,
) !ItemResult {
    const col_selected_active = c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0, .y = 0.478, .z = 0.8, .w = 1 });
    const col_selected_inactive = c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0.2, .y = 0.478, .z = 0.8, .w = 1 });
    const name = try allocator.dupeZ(u8, key);
    var is_selected = false;
    if (selected_file) |sel| {
        if (std.mem.eql(u8, sel, name)) is_selected = true;
    }
    c.ImGui_PushID(name.ptr);
    const pos = c.ImGui_GetCursorPos();
    const wrap_width = item_sz;
    const text_size = c.ImGui_CalcTextSizeEx(name.ptr, null, false, wrap_width);
    const btn_width = item_sz + (2 * style.FramePadding.x);
    const btn_height = item_sz + text_size.y + (2 * style.FramePadding.y);
    const btn_size = c.ImVec2{ .x = btn_width, .y = btn_height };
    if (is_selected)
        c.ImGui_PushStyleColor(
            c.ImGuiCol_Button,
            if (active) col_selected_active else col_selected_inactive,
        );
    const clicked = c.ImGui_ButtonEx("##name", btn_size);
    if (is_selected)
        c.ImGui_PopStyleColor();
    var result: ItemResult = .none;
    if (clicked)
        result = .click;
    if (c.ImGui_IsItemHovered(c.ImGuiHoveredFlags_None) and c.ImGui_IsMouseDoubleClicked(0))
        result = .double_click;
    c.ImGui_SetCursorPos(pos);
    const icon_x = pos.x + ((btn_size.x - item_sz) / 2);
    c.ImGui_SetCursorPosX(icon_x);
    _ = c.ImGui_Image(icon, c.ImVec2{ .x = item_sz, .y = item_sz });
    const text_y = pos.y + item_sz;
    const text_area_x = pos.x + ((btn_size.x - wrap_width) / 2) + ((wrap_width - text_size.x) / 2);
    c.ImGui_SetCursorPos(c.ImVec2{ .x = text_area_x, .y = text_y });
    c.ImGui_PushTextWrapPos(text_area_x + wrap_width);
    c.ImGui_TextWrapped(name.ptr);
    c.ImGui_PopTextWrapPos();
    c.ImGui_PopID();
    allocator.free(name);
    return result;
}

fn setProjectExplorerPath(self: *Self, path: []const u8) !void {
    const old_mem = self.project_explorer_path;
    self.project_explorer_path = try self.allocator.dupeZ(u8, path);
    self.allocator.free(old_mem);
}

fn setSelected(self: *Self, item: ?OrderedItem) !void {
    var ed = Editor.instance();
    if (self.selected_file) |it| {
        if (AssetsDatabase.getResourceId(it)) |u| {
            _ = ed.selection.remove(.resource, u);
        } else |_| {}
        self.allocator.free(it);
    }
    if (item) |it| {
        const path = it.key;
        if (it.res.node == .resource) {
            if (AssetsDatabase.getResourceId(it.res.node.path())) |u| {
                ed.selection = .{ .resource = u };
            } else |_| {}
        }
        self.selected_file = try self.allocator.dupeZ(u8, path);
    }
}
