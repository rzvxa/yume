const c = @import("clibs");

const std = @import("std");
const builtin = @import("builtin");

const utils = @import("yume").utils;

const imutils = @import("../imutils.zig");
const Editor = @import("../Editor.zig");
const Project = @import("../Project.zig");
const Resources = @import("../Resources.zig");
const ResourceNode = @import("../Resources.zig").ResourceNode;

const RType = Resources.Resource.Type;
const Node = ResourceNode.Node;

const Self = @This();

allocator: std.mem.Allocator,
state: State,
uri: Resources.Uri,
selected_file: ?ResourceNode.Node = null,
entering_renaming: bool = false,
is_focused: bool = false,
sort_by_name: bool = true,
editable_uri: bool = false,
entering_editable_uri: bool = false,
uri_str: imutils.ImString,
name_str: imutils.ImString,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .state = .normal,
        .uri = try Resources.Uri.parse(allocator, "project://"),
        .name_str = try imutils.ImString.init(allocator),
        .uri_str = try imutils.ImString.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.state.deinit(self.allocator);

    if (self.selected_file) |*it| {
        it.deinit(self.allocator);
    }

    self.name_str.deinit();
    self.uri_str.deinit();
    self.uri.deinit(self.allocator);
}

const ItemResult = union(enum) {
    none,
    click,
    double_click,
    name_double_click,
};

const OrderedItem = struct {
    key: [:0]const u8,
    res: *ResourceNode,
    type: Resources.Resource.Type,

    pub fn compare(_: void, a: OrderedItem, b: OrderedItem) bool {
        const a_is_dir = a.res.node == .directory;
        const b_is_dir = b.res.node == .directory;
        if (a_is_dir and !b_is_dir) return true;
        if (!a_is_dir and b_is_dir) return false;
        return std.mem.order(u8, a.key, b.key).compare(.lt);
    }
};

pub fn draw(self: *Self) !void {
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
    const bread_crumb_height = c.ImGui_GetFrameHeight() + (style.FramePadding.y * 2);
    const avail = c.ImGui_GetContentRegionAvail();
    const col_count: c_int = @intFromFloat(@max(1, avail.x / (item_sz + 32)));
    const view_size = c.ImVec2{ .x = avail.x, .y = avail.y - bread_crumb_height - 4 };

    const resource_node = (try Resources.findResourceNodeByUri(&self.uri)) orelse {
        self.setUri(try Resources.Uri.parse(self.allocator, "project://"));
        return;
    };

    var items = std.ArrayList(OrderedItem).init(self.allocator);
    defer items.deinit();
    var it = resource_node.children.iterator();
    while (it.next()) |entry| {
        try items.append(OrderedItem{
            .key = entry.key_ptr.*,
            .res = entry.value_ptr,

            .type = if (entry.value_ptr.node == .directory)
                .unknown
            else
                try Resources.getResourceType(entry.value_ptr.node.resource),
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
            const table_size = c.ImVec2{ .x = view_size.x, .y = view_size.y - 12 };
            const cursor = c.ImGui_GetCursorPos();
            c.ImGui_SetNextItemAllowOverlap();
            if (c.ImGui_InvisibleButton("resources-background", table_size, 0)) {
                try self.setSelected(null);
            }
            try self.drawBackgroundContextMenu();
            c.ImGui_SetCursorPos(cursor);
            const draw_table = c.ImGui_BeginTableEx(
                "node",
                col_count,
                table_flags,
                table_size,
                0,
            );
            defer c.ImGui_EndTable();

            if (draw_table) {
                const total_items: c_int = @intCast(items.items.len);
                const total_rows: c_int = @divTrunc((total_items + col_count - 1), col_count);

                var clipper = c.ImGuiListClipper{};
                c.ImGuiListClipper_Begin(&clipper, total_rows, item_sz);
                while (c.ImGuiListClipper_Step(&clipper)) {
                    var row = clipper.DisplayStart;
                    while (row < clipper.DisplayEnd) : (row += 1) {
                        c.ImGui_TableNextRow();
                        var col: c_int = 0;
                        while (col < col_count) : (col += 1) {
                            const index = row * col_count + col;
                            if (index >= total_items) break; // no more items to draw
                            _ = c.ImGui_TableNextColumn();

                            const item = items.items[@intCast(index)];
                            try self.enterItem(&item);
                            _ = try self.drawItem(item.key, &item.res.node, item.type, item_sz, style, false);
                            try self.leaveItem(&item);
                        }
                    }
                }
                c.ImGuiListClipper_End(&clipper);
            }
        }
    }
    try self.drawBreadCrumbs(bread_crumb_height);
}

fn drawItem(
    self: *Self,
    key: [:0]const u8,
    node: *const Node,
    typ: RType,
    item_sz: f32,
    style: c.ImGuiStyle,
    comptime headless: bool,
) !ItemResult {
    const is_root = self.uri.isRoot();
    const is_dir = node.* == .directory;
    const icon = blk: {
        if (is_root) {
            if (std.mem.eql(u8, key, "builtin")) {
                break :blk try Editor.getImGuiTexture("editor://icons/yume.png");
            } else if (std.mem.eql(u8, key, "project")) {
                break :blk try Editor.getImGuiTexture("editor://icons/library.png");
            } else if (std.mem.eql(u8, key, "editor")) {
                break :blk try Editor.getImGuiTexture("editor://icons/editor.png");
            } else {
                break :blk try Editor.getImGuiTexture("editor://icons/folder.png");
            }
        } else if (is_dir) {
            break :blk try Editor.getImGuiTexture("editor://icons/folder.png");
        } else if (typ != .unknown) {
            const possible_icon_path = typ.fileIconUri();
            break :blk Editor.getImGuiTexture(possible_icon_path) catch try Editor.getImGuiTexture("editor://icons/file.png");
        } else {
            break :blk try Editor.getImGuiTexture("editor://icons/file.png");
        }
    };

    const allocator = self.allocator;
    const col_selected_active = c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0, .y = 0.478, .z = 0.8, .w = 1 });
    const col_selected_inactive = c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0.2, .y = 0.478, .z = 0.8, .w = 1 });
    const name = try if (typ == .unknown) allocator.dupeZ(u8, key) else allocator.dupeZ(u8, std.fs.path.stem(key));
    defer allocator.free(name);
    const is_selected = if (self.selected_file) |sel| sel.eql(node) else false;
    const is_renaming = self.state.isRenaming(node);
    c.ImGui_PushID(key);
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
    try self.drawItemContextMenu(node, typ);
    if (is_selected)
        c.ImGui_PopStyleColor();
    var result: ItemResult = .none;
    if (clicked) {
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
            self.name_str.buf,
            @intCast(self.name_str.size()),
            .{ .x = btn_width, .y = 0 },
            c.ImGuiInputTextFlags_CallbackResize | c.ImGuiInputTextFlags_EnterReturnsTrue,
            &imutils.ImString.InputTextCallback,
            &self.name_str,
        );
        if (c.ImGui_IsItemDeactivated()) {
            if (c.ImGui_IsItemDeactivatedAfterEdit() and !c.ImGui_IsKeyPressed(c.ImGuiKey_Escape)) {
                const old_path = try node.path();
                var new_name_buf: [std.fs.max_path_bytes]u8 = undefined;
                const new_path = try std.fmt.bufPrint(&new_name_buf, "{s}/{s}{s}", .{
                    std.fs.path.dirname(old_path) orelse ".",
                    self.name_str.span(),
                    if (typ != .unknown) std.fs.path.extension(old_path) else "",
                });
                Resources.move(old_path, new_path) catch |err| {
                    std.log.err("failed to rename from \"{s}\" to \"{s}\", err: {}", .{ old_path, new_path, err });
                };
                if (self.selected_file) |sf| {
                    const uri = try node.uri();
                    var parent_uri = try uri.parentUriOr(.protocol_uri, allocator);
                    defer parent_uri.deinit(allocator);
                    var new_uri = try parent_uri.join(allocator, &.{
                        self.name_str.span(),
                        if (typ != .unknown) std.fs.path.extension(old_path) else "",
                    });
                    defer new_uri.deinit(allocator);
                    switch (sf) {
                        .root, .resource => {},
                        .directory => try self.setSelected(&.{ .directory = new_uri }),
                    }
                }
            }
            self.normal();
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

    if (comptime !headless) {
        switch (result) {
            .none => {},
            .click => try self.setSelected(node),
            .double_click => try self.open(node, typ),
            .name_double_click => {
                if (typ != .project) {
                    try self.rename(node, typ != .unknown);
                } else {
                    std.log.info("Can't rename the project file", .{});
                }
            },
        }
    }
    return result;
}

fn drawBreadCrumbs(self: *Self, bread_crumb_height: f32) !void {
    var sfa_heap = std.heap.stackFallback(2048, self.allocator);
    const allocator = sfa_heap.get();
    const crumb_total_avail = c.ImGui_GetContentRegionAvail();
    _ = c.ImGui_BeginChildFrame(c.ImGui_GetID("bread-crumb-frame"), .{ .x = crumb_total_avail.x, .y = bread_crumb_height });
    defer c.ImGui_EndChildFrame();
    {
        const cursor = c.ImGui_GetCursorPos();
        defer c.ImGui_SetCursorPos(cursor);
        c.ImGui_SetNextItemAllowOverlap();
        _ = c.ImGui_InvisibleButton("bread-crumb-frame-btn", .{ .x = crumb_total_avail.x, .y = bread_crumb_height - 8 }, 0);
        if (c.ImGui_IsItemHovered(c.ImGuiHoveredFlags_None) and c.ImGui_IsMouseDoubleClicked(0)) {
            try self.editableUri(true);
        }
    }

    if (self.editable_uri) {
        if (self.entering_editable_uri) {
            c.ImGui_SetKeyboardFocusHere();
            self.entering_editable_uri = false;
        }
        _ = c.ImGui_InputTextWithHintAndSizeEx(
            "##uri-input",
            null,
            self.uri_str.buf,
            @intCast(self.uri_str.size()),
            .{ .x = crumb_total_avail.x - 8, .y = crumb_total_avail.y - 8 },
            c.ImGuiInputTextFlags_CallbackResize | c.ImGuiInputTextFlags_EnterReturnsTrue | c.ImGuiInputTextFlags_AutoSelectAll,
            &imutils.ImString.InputTextCallback,
            &self.uri_str,
        );

        if (c.ImGui_IsItemDeactivated()) {
            defer self.editableUri(false) catch {};
            if (c.ImGui_IsItemDeactivatedAfterEdit() and !c.ImGui_IsKeyPressed(c.ImGuiKey_Escape)) {
                const new_uri_span = self.uri_str.span();
                var new_uri = Resources.Uri.parse(self.allocator, new_uri_span) catch |err| {
                    std.log.err("{}, URI: \"{s}\"", .{ err, new_uri_span });
                    return;
                };
                if (try Resources.findResourceNodeByUri(&new_uri)) |_| {
                    self.setUri(new_uri);
                } else {
                    std.log.err("URI does not exists: \"{s}\"", .{new_uri.span()});
                    new_uri.deinit(self.allocator);
                }
            }
        }
        return;
    }

    // draw the root button independent of number of crumbs, it never gets collapsed and is always present
    const home_height = c.ImGui_GetTextLineHeight();
    if (c.ImGui_ImageButton("root", try Editor.getImGuiTexture("editor://icons/home.png"), .{ .x = home_height, .y = home_height })) {
        self.setUri(try Resources.Uri.parse(self.allocator, ":://"));
    }

    var uri = try self.uri.clone(allocator);
    defer uri.deinit(allocator);

    var crumbs = std.ArrayList(Resources.Uri.ComponentIterator.Result).init(allocator);
    defer crumbs.deinit();
    var crumb_widths = std.ArrayList(f32).init(allocator);
    defer crumb_widths.deinit();

    const button_padding = 10;
    const sep_padding: f32 = 8.0;
    const sep_first_width = c.ImGui_CalcTextSize("://").x;
    const sep_width: f32 = c.ImGui_GetFrameHeight();

    { // sizing
        var iter = uri.componentIterator();
        var i: usize = 0;

        while (iter.next()) |crumb| : (i += 1) {
            // skip the root protocol `:` in `:://a/b/c` URIs we use the home button for it
            if (i == 0 and uri.isInRoot()) {
                continue;
            }

            try crumbs.append(crumb);

            const name = try allocator.dupeZ(u8, crumb.name);
            defer allocator.free(name);
            const text_size = c.ImGui_CalcTextSize(name);
            var btn_width = text_size.x + button_padding;
            if (iter.peek()) |_| {
                if ((i == 1 and uri.isInRoot()) or i == 0) {
                    btn_width += sep_first_width;
                } else {
                    btn_width += sep_width;
                }
                btn_width += sep_padding;
            }
            try crumb_widths.append(btn_width);
        }
    }

    // nothing to draw
    if (crumbs.items.len == 0) {
        return;
    }

    var head_len: usize = 0;
    // by default collapse everything but last item
    var collapsed_len: usize = crumb_widths.items.len - 1;

    const min_prefered_tail = 2; // it is always one more, since last item is drawn regardless
    const min_prefered_head = 2;
    const min_ellipsis_width = c.ImGui_CalcTextSize("...").x + c.ImGui_GetStyle().*.FramePadding.x + sep_width + sep_padding;

    const empty_room = visibility_checks: {
        if (crumbs.items.len <= 1) { // not enough items to need a visibility check
            break :visibility_checks 0;
        }
        var avail_width = crumb_total_avail.x - home_height - crumb_widths.getLast() - min_ellipsis_width;

        { // in the first pass, we make sure `min_prefered_tail` items are visible
            var i = @as(isize, @intCast(crumbs.items.len)) - 2;
            var j: usize = 1;
            while (i >= 0 and j < min_prefered_tail) : ({
                i -= 1;
                j += 1;
            }) {
                const crumb_width = crumb_widths.items[@intCast(i)];
                if (crumb_width > avail_width) {
                    break :visibility_checks avail_width;
                }

                avail_width -= crumb_width;
                collapsed_len -= 1;
            }
        }

        { // the second pass, makes sure `min_prefered_head` items are visible
            const start_of_tail = collapsed_len;
            for (0..start_of_tail) |i| {
                if (i >= min_prefered_head) {
                    break;
                }

                const crumb_width = crumb_widths.items[i];
                if (crumb_width > avail_width) {
                    break :visibility_checks avail_width;
                }

                avail_width -= crumb_width;
                collapsed_len -= 1;
                head_len += 1;
            }
        }

        // finally we visit everything in between in reverse order
        // segments closer to the tail are higher priorities for visibility

        var i = @as(isize, @intCast(head_len + collapsed_len)) - 1;
        while (i >= head_len) : (i -= 1) {
            const crumb_width = crumb_widths.items[@intCast(i)];
            // can't display anymore crumbs
            if (crumb_width > avail_width) {
                break :visibility_checks avail_width;
            }

            avail_width -= crumb_width;
            collapsed_len -= 1;
        }

        break :visibility_checks avail_width;
    };

    { // draw head items
        c.ImGui_SameLineEx(0, 0);
        for (crumbs.items[0..head_len], 0..) |crumb, i| {
            const name = try allocator.dupeZ(u8, crumb.name);
            defer allocator.free(name);
            switch (drawBreadCrumb(@intCast(i), name, i > 0)) {
                .none => {},
                .click => self.setUri(try Resources.Uri.parse(self.allocator, crumb.uri)),
                .double_click => try self.editableUri(true),
            }
        }
    }

    if (collapsed_len > 0) { // draw the ellipsis and collapsed popup
        c.ImGui_SameLineEx(0, 0);
        const size = c.ImVec2{
            .x = min_ellipsis_width + empty_room - sep_width - sep_padding,
            .y = c.ImGui_GetFrameHeight(),
        };
        _ = c.ImGui_ButtonEx("...", size);
        if (c.ImGui_BeginPopupContextItemEx("bread-crumb-collapsed-menu", c.ImGuiPopupFlags_MouseButtonLeft)) {
            defer c.ImGui_EndPopup();
            const last_head_uri_len = if (head_len > 0) crumbs.items[head_len - 1].uri.len else 0;
            for (crumbs.items[head_len .. head_len + collapsed_len]) |crumb| {
                const name = try allocator.dupeZ(u8, crumb.uri[last_head_uri_len..]);
                defer allocator.free(name);
                if (c.ImGui_MenuItem(name)) {
                    self.setUri(try Resources.Uri.parse(self.allocator, crumb.uri));
                }
            }
        }

        c.ImGui_SameLineEx(0, 0);
        c.ImGui_BeginDisabled(true);
        _ = c.ImGui_ArrowButton("sep", c.ImGuiDir_Right);
        c.ImGui_EndDisabled();
    }

    { // draw tail items
        c.ImGui_SameLineEx(0, 0);
        for (crumbs.items[head_len + collapsed_len ..], head_len + collapsed_len..) |crumb, i| {
            const name = try allocator.dupeZ(u8, crumb.name);
            defer allocator.free(name);
            switch (drawBreadCrumb(@intCast(i), name, i > 0)) {
                .none => {},
                .click => self.setUri(try Resources.Uri.parse(self.allocator, crumb.uri)),
                .double_click => try self.editableUri(true),
            }
        }
    }
}

const DrawBreadCrumbResult = enum { none, click, double_click };

fn drawBreadCrumb(id: c_int, name: [*:0]const u8, arrow_sep: bool) DrawBreadCrumbResult {
    var result = DrawBreadCrumbResult.none;
    c.ImGui_PushIDInt(@intCast(id));
    defer c.ImGui_PopID();
    if (c.ImGui_Button(name)) {
        result = .click;
    }
    if (c.ImGui_IsItemHovered(c.ImGuiHoveredFlags_None) and c.ImGui_IsMouseDoubleClicked(0)) {
        result = .double_click;
    }
    c.ImGui_SameLineEx(0, 0);
    c.ImGui_BeginDisabled(true);
    if (arrow_sep) {
        _ = c.ImGui_ArrowButton("sep", c.ImGuiDir_Right);
    } else {
        _ = c.ImGui_Button("://");
    }
    c.ImGui_EndDisabled();
    c.ImGui_SameLineEx(0, 0);
    return result;
}

fn drawItemContextMenu(self: *Self, node: *const Node, ty: Resources.Resource.Type) !void {
    if (c.ImGui_BeginPopupContextItemEx("context-menu", c.ImGuiPopupFlags_MouseButtonRight)) {
        defer c.ImGui_EndPopup();
        if (c.ImGui_MenuItem("Open")) {
            try self.open(node, ty);
        }
        if (c.ImGui_MenuItem(switch (builtin.os.tag) {
            .macos => "Find in Finder",
            .windows => "Reveal in Explorer",
            else => "Reveal in File Manager",
        })) {
            try self.reveal(node);
        }
        c.ImGui_Separator();
        if (c.ImGui_MenuItem("Cut*")) {}
        if (c.ImGui_MenuItem("Copy*")) {}
        if (c.ImGui_MenuItem("Paste*")) {}

        if (c.ImGui_MenuItem("Delete*")) {}
    }
}

fn drawBackgroundContextMenu(self: *Self) !void {
    if (c.ImGui_BeginPopupContextItemEx("background-context-menu", c.ImGuiPopupFlags_MouseButtonRight)) {
        const readonly = !self.uri.isProject(); // TODO: Resources should provide this stat

        if (readonly) {
            c.ImGui_BeginDisabled(true);
        }
        if (c.ImGui_MenuItem("New Directory")) {
            var buf1: [std.fs.max_path_bytes]u8 = undefined;
            var buf2: [std.fs.max_path_bytes]u8 = undefined;
            var buf3: [std.fs.max_path_bytes]u8 = undefined;
            var i: usize = 0;
            while (true) : (i += 1) {
                const possible_name = if (i == 0)
                    "New Directory"
                else
                    try std.fmt.bufPrint(&buf1, "New Directory ({d})", .{i});

                const explorer_fullpath = try self.uri.bufFullpath(&buf2);
                const possible_path = try std.fmt.bufPrintZ(&buf3, "{s}/{s}", .{ explorer_fullpath, possible_name });

                std.fs.cwd().makeDir(possible_path) catch |err| switch (err) {
                    error.PathAlreadyExists => continue,
                    else => return err,
                };

                const uri = try self.uri.join(self.allocator, &.{possible_name});
                self.state = .{ .new = uri };
                break;
            }
        }

        if (readonly) {
            c.ImGui_EndDisabled();
        }

        c.ImGui_Separator();

        if (c.ImGui_MenuItem(switch (builtin.os.tag) {
            .macos => "Find in Finder",
            .windows => "Reveal in Explorer",
            else => "Reveal in File Manager",
        })) {
            try self.reveal(&Node{ .directory = self.uri });
        }

        c.ImGui_EndPopup();
    }
}

fn open(self: *Self, node: *const Node, ty: Resources.Resource.Type) !void {
    switch (node.*) {
        .resource => |r| {
            switch (ty) {
                .scene => try Editor.instance().openScene(.{ .uuid = r }),
                else => {
                    var buf: [std.fs.max_path_bytes]u8 = undefined;
                    try utils.tryOpenWithOsDefaultApplication(self.allocator, try Resources.bufResourceFullpath(r, &buf));
                },
            }
        },
        .directory => |d| self.setUri(try d.clone(self.allocator)),
        .root => self.setUri(try Resources.Uri.parse(self.allocator, ":://")),
    }
}

fn reveal(self: *Self, node: *const Node) !void {
    switch (node.*) {
        .root => return error.CanNotRevealRoot,
        .resource => |r| {
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            try utils.tryRevealPathInOsFileManager(self.allocator, try Resources.bufResourceFullpath(r, &buf));
        },
        .directory => |d| {
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            try utils.tryRevealPathInOsFileManager(self.allocator, try d.bufFullpath(&buf));
        },
    }
}

fn editableUri(self: *Self, editable: bool) !void {
    if (editable) {
        try self.uri_str.set(self.uri.span());
        self.editable_uri = true;
        self.entering_editable_uri = true;
    } else {
        self.editable_uri = false;
        self.entering_editable_uri = false;
    }
}

fn setUri(self: *Self, uri: Resources.Uri) void {
    var old_mem = self.uri;
    defer old_mem.deinit(self.allocator);
    self.normal();
    self.uri = uri;
}

fn setSelected(self: *Self, node: ?*const Node) !void {
    var ed = Editor.instance();
    self.normal();
    if (self.selected_file) |*it| {
        switch (it.*) {
            .root => {},
            .resource => |u| _ = ed.selection.remove(.resource, u),
            .directory => {},
        }
        it.deinit(self.allocator);
        self.selected_file = null;
    }
    if (node) |it| {
        if (it.* == .resource) {
            if (Resources.getResourceId(try it.path())) |u| {
                ed.selection = .{ .resource = u };
            } else |_| {}
        }
        self.selected_file = try it.clone(self.allocator);
    }
}

fn rename(self: *Self, node: *const Node, hide_ext: bool) !void {
    const key = std.fs.path.basename(try node.path());
    const name = if (hide_ext) std.fs.path.stem(key) else key;

    try self.name_str.set(name);

    try self.setSelected(node);

    self.state.deinit(self.allocator);
    self.state = .{ .renaming = try node.clone(self.allocator) };
    self.entering_renaming = true;
}

fn normal(self: *Self) void {
    self.state.deinit(self.allocator);
    self.state = .normal;
}

fn enterItem(self: *Self, item: *const OrderedItem) !void {
    switch (self.state) {
        .new => |*uri| if ((try item.res.node.uri()).eql(uri)) {
            return self.rename(&item.res.node, item.type != .unknown);
        },
        else => {},
    }
}

fn leaveItem(self: *Self, item: *const OrderedItem) !void {
    _ = self;
    _ = item;
}

const State = union(enum) {
    // normal mode
    normal,
    // renaming a node
    renaming: ResourceNode.Node,
    // created a path, gets promoted to renaming as soon as the path is registered and drawn
    new: Resources.Uri,

    fn deinit(state: *State, allocator: std.mem.Allocator) void {
        switch (state.*) {
            .normal => {},
            inline .new, .renaming => |*it| it.deinit(allocator),
        }
    }

    fn isRenaming(state: State, node: *const ResourceNode.Node) bool {
        return switch (state) {
            .renaming => |*n| n.eql(node),
            else => false,
        };
    }
};
