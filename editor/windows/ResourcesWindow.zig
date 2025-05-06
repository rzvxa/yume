const c = @import("clibs");

const std = @import("std");

const utils = @import("yume").utils;

const imutils = @import("../imutils.zig");
const Editor = @import("../Editor.zig");
const Project = @import("../Project.zig");
const Resources = @import("../Resources.zig");
const ResourceNode = @import("../Resources.zig").ResourceNode;

const Self = @This();

allocator: std.mem.Allocator,
explorer_uri: ?Resources.Uri,
selected_file: ?ResourceNode.Node = null,
renaming_file: ?ResourceNode.Node = null,
entering_renaming: bool = false,
is_focused: bool = false,
sort_by_name: bool = true,
renaming_str: imutils.ImString,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .explorer_uri = try Resources.Uri.parse(allocator, "assets://"),
        .renaming_str = try imutils.ImString.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    if (self.selected_file) |*it| {
        it.deinit(self.allocator);
    }

    if (self.renaming_file) |*it| {
        it.deinit(self.allocator);
    }

    self.renaming_str.deinit();
    if (self.explorer_uri) |*uri| uri.deinit(self.allocator);
}

pub const ItemResult = union(enum) {
    none,
    click,
    double_click,
    name_double_click,
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
    const window_open = c.ImGui_Begin("Resources", null, c.ImGuiWindowFlags_NoCollapse);
    self.is_focused = c.ImGui_IsWindowFocused(0);
    defer c.ImGui_End();
    if (!window_open) return;
    if (Project.current() == null) {
        c.ImGui_Text("No Loaded Project!");
        return;
    }
    const item_sz: f32 = 64;
    const style = c.ImGui_GetStyle().*;
    const bread_crumb_height = c.ImGui_GetFrameHeight() + style.FramePadding.y;
    const avail = c.ImGui_GetContentRegionAvail();
    const col_count = @max(1, avail.x / (item_sz + 32));
    const view_size = c.ImVec2{ .x = avail.x, .y = avail.y - bread_crumb_height - 1 };

    const explorer_path = if (self.explorer_uri) |uri| uri.span() else "";

    const resource_node = (try Resources.findResourceNodeByUri(explorer_path)) orelse {
        try self.setExplorerPath("assets://");
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

    {
        const draw_frame = c.ImGui_BeginChildFrameEx(c.ImGui_GetID("files grid"), view_size, c.ImGuiWindowFlags_NoBackground);
        defer c.ImGui_EndChildFrame();
        if (draw_frame) {
            const table_flags = c.ImGuiTableFlags_SizingStretchSame;
            const draw_table = c.ImGui_BeginTableEx("node", @intFromFloat(col_count), table_flags, .{ .x = view_size.x, .y = view_size.y - 12 }, 0);
            defer c.ImGui_EndTable();
            if (draw_table) {
                var index: usize = 0;
                for (items.items) |item| {
                    if (index % @as(usize, @intFromFloat(col_count)) == 0) {
                        c.ImGui_TableNextRow();
                    }
                    _ = c.ImGui_TableNextColumn();

                    try self.drawItem(item, item_sz, style);
                    index += 1;
                }
            }
        }
    }

    const home_height = c.ImGui_GetTextLineHeight();
    if (c.ImGui_ImageButton("root", try Editor.getImGuiTexture("editor://icons/home.png"), .{ .x = home_height, .y = home_height })) {
        try self.setExplorerPath(null);
    }
    if (self.explorer_uri) |uri_borrowed| {
        var uri = try uri_borrowed.clone(allocator);
        defer uri.deinit(allocator);
        c.ImGui_SameLineEx(0, 0);
        var crumbs = uri.componentIterator();
        var i: c_int = 0;
        while (crumbs.next()) |crumb| : (i += 1) {
            c.ImGui_PushIDInt(i);
            defer c.ImGui_PopID();
            const name = try allocator.dupeZ(u8, crumb.name);
            defer allocator.free(name);
            if (c.ImGui_Button(name)) {
                try self.setExplorerPath(crumb.uri);
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
}

fn drawItem(
    self: *Self,
    item_const: OrderedItem,
    item_sz: f32,
    style: c.ImGuiStyle,
) !void {
    var item = item_const;
    const is_root = self.explorer_uri == null;
    const is_dir = item.res.node == .directory;
    const resource_type: Resources.Resource.Type = blk: {
        if (is_dir) {
            break :blk .unknown;
        }
        break :blk try Resources.getResourceType(item.res.node.resource);
    };
    const icon = blk: {
        if (is_root) {
            if (std.mem.eql(u8, item.key, "builtin")) {
                break :blk try Editor.getImGuiTexture("editor://icons/yume.png");
            } else if (std.mem.eql(u8, item.key, "assets")) {
                break :blk try Editor.getImGuiTexture("editor://icons/library.png");
            } else if (std.mem.eql(u8, item.key, "editor")) {
                break :blk try Editor.getImGuiTexture("editor://icons/editor.png");
            } else {
                break :blk try Editor.getImGuiTexture("editor://icons/folder.png");
            }
        } else if (is_dir) {
            break :blk try Editor.getImGuiTexture("editor://icons/folder.png");
        } else if (resource_type != .unknown) {
            const possible_icon_path = resource_type.fileIconUri();
            break :blk Editor.getImGuiTexture(possible_icon_path) catch try Editor.getImGuiTexture("editor://icons/file.png");
        } else {
            break :blk try Editor.getImGuiTexture("editor://icons/file.png");
        }
    };

    const allocator = self.allocator;
    const col_selected_active = c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0, .y = 0.478, .z = 0.8, .w = 1 });
    const col_selected_inactive = c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0.2, .y = 0.478, .z = 0.8, .w = 1 });
    const name = try if (resource_type == .unknown) allocator.dupeZ(u8, item.key) else allocator.dupeZ(u8, std.fs.path.stem(item.key));
    defer allocator.free(name);
    const is_selected = if (self.selected_file) |sel| sel.eql(&item.res.node) else false;
    const is_renaming = if (self.renaming_file) |ren| ren.eql(&item.res.node) else false;
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
            if (self.is_focused) col_selected_active else col_selected_inactive,
        );
    c.ImGui_SetNextItemAllowOverlap();
    const clicked = c.ImGui_ButtonEx("##name", btn_size);
    if (is_selected)
        c.ImGui_PopStyleColor();
    var result: ItemResult = .none;
    if (clicked) {
        if (!is_root) {
            std.log.debug("click: {s}", .{item.res.node.uri() catch @panic("We")});
        }
        result = .click;
    }
    if (c.ImGui_IsItemHovered(c.ImGuiHoveredFlags_None) and c.ImGui_IsMouseDoubleClicked(0)) {
        result = .double_click;
    }
    c.ImGui_SetCursorPos(pos);
    const icon_x = pos.x + ((btn_size.x - item_sz) / 2);
    c.ImGui_SetCursorPosX(icon_x);
    _ = c.ImGui_Image(icon, c.ImVec2{ .x = item_sz, .y = item_sz });
    const text_y = pos.y + item_sz;
    if (is_renaming) {
        c.ImGui_SetCursorPosY(text_y);
        if (self.entering_renaming) {
            c.ImGui_SetKeyboardFocusHere();
            self.entering_renaming = false;
        }
        _ = c.ImGui_InputTextWithHintAndSizeEx(
            "##renaming-input",
            null,
            self.renaming_str.buf,
            @intCast(self.renaming_str.size()),
            .{ .x = btn_width, .y = 0 },
            c.ImGuiInputTextFlags_CallbackResize | c.ImGuiInputTextFlags_EnterReturnsTrue,
            &imutils.ImString.InputTextCallback,
            &self.renaming_str,
        );
        if (c.ImGui_IsItemDeactivated()) {
            if (c.ImGui_IsItemDeactivatedAfterEdit() and !c.ImGui_IsKeyPressed(c.ImGuiKey_Escape)) {
                std.log.info("new name: {s}", .{self.renaming_str.buf});
                const old_path = try item.res.node.path();
                var new_name_buf: [256]u8 = undefined;
                const new_path = try std.fmt.bufPrint(&new_name_buf, "{s}/{s}{s}", .{
                    std.fs.path.dirname(old_path) orelse ".",
                    self.renaming_str.span(),
                    std.fs.path.extension(old_path),
                });
                std.log.err("old_path: {s}, new_path: {s}", .{ old_path, new_path });
                Resources.move(old_path, new_path) catch |err| {
                    std.log.err("failed to rename from \"{s}\" to \"{s}\", err: {}", .{ old_path, new_path, err });
                };
            }
            _ = try self.setRenaming(null);
        }
    } else {
        const text_area_x = pos.x + ((btn_size.x - wrap_width) / 2) + ((wrap_width - text_size.x) / 2);
        c.ImGui_SetCursorPos(c.ImVec2{ .x = text_area_x, .y = text_y });
        c.ImGui_PushTextWrapPos(text_area_x + wrap_width);
        c.ImGui_TextWrapped(name.ptr);
        if (c.ImGui_IsItemHovered(c.ImGuiHoveredFlags_AllowWhenBlockedByActiveItem) and c.ImGui_IsMouseDoubleClicked(0)) {
            result = .name_double_click;
        }
        c.ImGui_PopTextWrapPos();
    }
    c.ImGui_PopID();

    if (result == .none) {
        if (is_selected and c.ImGui_IsKeyPressed(c.ImGuiKey_F2)) {
            result = .name_double_click;
        }
    }

    switch (result) {
        .none => {},
        .click => try self.setSelected(item),
        .double_click => {
            switch (item.res.node) {
                .resource => |r| {
                    switch (resource_type) {
                        .scene => try Editor.instance().openScene(r),
                        else => {
                            var buf: [std.fs.max_path_bytes]u8 = undefined;
                            try utils.tryOpenWithOsDefaultApplication(self.allocator, try Resources.bufResourceFullpath(r, &buf));
                        },
                    }
                },
                .directory => |d| try self.setExplorerPath(d.span()),
                .root => try self.setExplorerPath(null),
            }
        },
        .name_double_click => {
            if (resource_type != .project) {
                try self.setSelected(item);
                try self.renaming_str.set(std.fs.path.stem(name));
                try self.setRenaming(item);
            } else {
                std.log.info("Can't rename the project file", .{});
            }
        },
    }
}

fn setExplorerPath(self: *Self, path: ?[]const u8) !void {
    if (path) |p| std.log.debug("setExplorerPath: {s}", .{p});
    var old_mem = self.explorer_uri;
    _ = try self.setRenaming(null);
    self.explorer_uri = if (path) |p| try Resources.Uri.parse(self.allocator, p) else null;
    if (old_mem) |*uri| uri.deinit(self.allocator);
}

fn setSelected(self: *Self, item: ?OrderedItem) !void {
    var ed = Editor.instance();
    _ = try self.setRenaming(null);
    if (self.selected_file) |*it| {
        switch (it.*) {
            .root => {},
            .resource => |u| _ = ed.selection.remove(.resource, u),
            .directory => {},
        }
        it.deinit(self.allocator);
        self.selected_file = null;
    }
    if (item) |it| {
        if (it.res.node == .resource) {
            if (Resources.getResourceId(try it.res.node.path())) |u| {
                ed.selection = .{ .resource = u };
            } else |_| {}
        }
        self.selected_file = try it.res.node.clone(self.allocator);
    }
}

fn setRenaming(self: *Self, item: ?OrderedItem) !void {
    if (self.renaming_file) |*it| {
        it.deinit(self.allocator);
        self.renaming_file = null;
    }
    if (item) |it| {
        self.renaming_file = try it.res.node.clone(self.allocator);
        self.entering_renaming = true;
    }
}
