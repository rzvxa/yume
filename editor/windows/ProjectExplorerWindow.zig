const c = @import("clibs");
const std = @import("std");

const Uuid = @import("yume").Uuid;
const GameApp = @import("yume").GameApp;
const ecs = @import("yume").ecs;
const utils = @import("yume").utils;
const Rect = @import("yume").Rect;
const Event = @import("yume").Event;
const collections = @import("yume").collections;
const assets = @import("yume").assets;

const Editor = @import("../Editor.zig");
const EditorDatabase = @import("../EditorDatabase.zig");
const Resources = @import("../Resources.zig");
const imutils = @import("../imutils.zig");

const Range = utils.Range;
const lerp = std.math.lerp;

const log = std.log.scoped(.ProjectExplorer);

pub const OnPick = Event(.{*const Resources.Resource});
pub const ModalEvent = Event(.{?*const Resources.Resource});

const Self = @This();

allocator: std.mem.Allocator,
visible: bool = false,
request_open: bool = false,
request_close: bool = false,
request_focus: bool = true,

anim_alpha: f32 = 0,
anim_window_height: f32 = 0,
anim_window_width: f32 = 0,

filters: collections.StringSentinelArrayHashMap(0, Filter),
locked_filters: collections.StringSentinelArrayHashMap(0, Filter),

find_str: imutils.ImString,

index: collections.StringSentinelArrayHashMap(0, *Entry),
matches: std.ArrayList(Match),
selected: usize = 0,

// there is only one active modal callback, set by the caller of browse.
modal_callback: ModalEvent.List,
on_pick: OnPick.List,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .filters = collections.StringSentinelArrayHashMap(0, Filter).init(allocator),
        .locked_filters = collections.StringSentinelArrayHashMap(0, Filter).init(allocator),
        .find_str = try imutils.ImString.init(allocator),
        .index = collections.StringSentinelArrayHashMap(0, *Entry).init(allocator),
        .matches = std.ArrayList(Match).init(allocator),

        .modal_callback = ModalEvent.List.init(allocator),
        .on_pick = OnPick.List.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.filters.deinit();
    self.locked_filters.deinit();
    self.find_str.deinit();

    Resources.onRegister().remove(.always, Resources.OnRegisterEvent.callback(Self, self, &Self.onResourcesRegister)) catch {};
    Resources.onUnregister().remove(.always, Resources.OnUnregisterEvent.callback(Self, self, &Self.onResourcesUnregister)) catch {};
    Resources.onReinit().remove(.always, Resources.OnReinitEvent.callback(Self, self, &Self.onResourcesReinit)) catch {};

    self.invalidateCaches(.{ .hard = true });
    self.modal_callback.deinit();
    self.on_pick.deinit();

    {
        defer self.index.deinit();
        var values = self.index.values();
        for (0..values.len) |i| {
            values[i].deinit(self.allocator);
            self.allocator.destroy(values[i]);
        }
    }
}

pub fn setup(self: *Self) !void {
    self.onResourcesReinit();

    try Resources.onRegister().append(.always, Resources.OnRegisterEvent.callback(Self, self, &Self.onResourcesRegister));
    try Resources.onUnregister().append(.always, Resources.OnUnregisterEvent.callback(Self, self, &Self.onResourcesUnregister));
    try Resources.onReinit().append(.always, Resources.OnReinitEvent.callback(Self, self, &Self.onResourcesReinit));
}

pub fn browse(
    self: *Self,
    selected: ?Selector,
    opts: struct {
        locked_filters: []const Filter,
        filters: []const Filter,
        // callback only owns the entry for the duration of the call
        callback: ModalEvent.Callback,
    },
) !void {
    self.locked_filters.clearRetainingCapacity();
    self.filters.clearRetainingCapacity();
    for (opts.locked_filters) |filter| {
        try self.locked_filters.put(filter.tag_name.span(), filter);
    }
    for (opts.filters) |filter| {
        try self.filters.put(filter.tag_name.span(), filter);
    }
    self.selected = 0;
    var found_entry: ?[:0]const u8 = null;
    if (selected) |sel| {
        var iter = self.index.iterator();
        switch (sel) {
            .filter => |s| while (iter.next()) |it| {
                if (it.value_ptr.*.kind == .filter and std.mem.eql(u8, it.value_ptr.*.kind.filter.tag_name.span(), s)) {
                    found_entry = it.key_ptr.*;
                }
            },
            .resource => |u| while (iter.next()) |it| {
                if (it.value_ptr.*.kind == .resource and it.value_ptr.*.kind.resource.id.eql(u)) {
                    found_entry = it.key_ptr.*;
                }
            },
        }
    }

    if (found_entry) |entry| {
        try self.find_str.set(entry);
    }

    self.updateQueries();
    self.modal_callback.clearRetainingCapacity();
    try self.modal_callback.append(.once, opts.callback);
    self.request_open = true;
}

pub fn draw(self: *Self, ctx: *GameApp) !void {
    if (self.request_open or (c.ImGui_IsKeyDown(c.ImGuiKey_ModCtrl) and c.ImGui_IsKeyPressed(c.ImGuiKey_P))) {
        if (!self.visible) {
            self.visible = true;
            c.ImGui_OpenPopup("Project Explorer", 0);
        }
        self.request_focus = true;
        self.request_open = false;
    } else if (self.request_close) {
        if (self.visible) {
            self.visible = false;
            c.ImGui_CloseCurrentPopup();
        }
        self.request_close = false;
    }

    const app_window_extent = ctx.windowExtent().toVec2();
    const target_window_width = if (!self.visible and self.find_str.length() == 0) 80 else @min(800, app_window_extent.x * 0.4);
    const input_height = 50;
    // if there is search text, add extra height for the gallery.
    const target_window_height = if (self.find_str.length() > 0)
        input_height + app_window_extent.y * 0.4 + 40
    else
        input_height;

    // update our tweened values.
    self.anim_alpha = lerp(self.anim_alpha, @as(f32, if (self.visible) 1.0 else 0.0), 0.1);
    self.anim_window_width = lerp(self.anim_window_width, target_window_width, 0.1);
    self.anim_window_height = lerp(self.anim_window_height, target_window_height, 0.1);

    const input_width = target_window_width;

    const window_padding = c.ImGui_GetStyle().*.WindowPadding;
    {
        // center the window horizontally and position it at 20% from the top.
        c.ImGui_SetNextWindowPos(.{ .x = app_window_extent.x / 2 - input_width / 2, .y = app_window_extent.y * 0.2 }, c.ImGuiCond_Appearing);
        c.ImGui_SetNextWindowSize(.{
            .x = self.anim_window_width + window_padding.x * 3,
            .y = self.anim_window_height + window_padding.y + 2,
        }, c.ImGuiCond_Always);
        c.ImGui_PushStyleColorImVec4(
            c.ImGuiCol_ModalWindowDimBg,
            .{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 0.3 },
        );
        // Push our tweened alpha for smooth fade in/out.
        c.ImGui_PushStyleVar(c.ImGuiStyleVar_Alpha, self.anim_alpha);
        defer c.ImGui_PopStyleVar();
        defer c.ImGui_PopStyleColor();
        const pre_begin_visible = self.visible;
        if (!c.ImGui_BeginPopupModal(
            "Project Explorer",
            &self.visible,
            c.ImGuiWindowFlags_NoDocking |
                c.ImGuiWindowFlags_NoSavedSettings |
                c.ImGuiWindowFlags_NoResize |
                c.ImGuiWindowFlags_NoScrollbar |
                c.ImGuiWindowFlags_NoScrollWithMouse |
                c.ImGuiWindowFlags_NoTitleBar |
                c.ImGuiWindowFlags_NoCollapse,
        )) {
            if (pre_begin_visible) { // modal just closed
                self.modal_callback.fire(.{null});
            }
            return;
        }
        c.ImGui_SetScrollY(0);
    }
    defer c.ImGui_EndPopup();

    {
        c.ImGui_PushStyleColorImVec4(
            c.ImGuiCol_FrameBg,
            std.mem.zeroes(c.ImVec4),
        );
        defer c.ImGui_PopStyleColor();
        c.ImGui_Image(try Editor.getImGuiTexture("editor://icons/search.png"), .{ .x = input_height - 8, .y = input_height - 8 });
        c.ImGui_SameLine();
        const drawn_tags = try drawTagsGrid(self.locked_filters.keys(), self.filters.keys(), @divTrunc(input_width, 3), input_height - 8);
        c.ImGui_SameLine();
        if (drawn_tags.clicked_index) |clicked| {
            self.filters.orderedRemoveAt(clicked);
        }

        {
            c.ImGui_PushFont(Editor.ubuntu24);
            defer c.ImGui_PopFont();
            if (self.request_focus) {
                self.request_focus = false;
                c.ImGui_SetKeyboardFocusHere();
            }
            if (c.ImGui_InputTextWithHintAndSizeEx(
                "##find-query",
                "Start typing...",
                self.find_str.buf,
                @intCast(self.find_str.size()),
                .{ .x = input_width - 8 - input_height - drawn_tags.width, .y = input_height - 8 },
                c.ImGuiInputTextFlags_CallbackResize | c.ImGuiInputTextFlags_AutoSelectAll,
                &imutils.ImString.InputTextCallback,
                &self.find_str,
            )) {
                self.updateQueries();
            } else if (self.find_str.length() == 0 and
                self.filters.count() > 0 and
                c.ImGui_IsItemFocused() and
                c.ImGui_IsKeyPressed(c.ImGuiKey_Backspace))
            {
                self.filters.orderedRemoveAt(self.filters.count() - 1);
            }
        }
    }

    if (self.find_str.length() == 0) {
        return;
    }

    const edb = &EditorDatabase.storage().project_explorer;

    {
        const grid_icon = try Editor.getImGuiTexture("editor://icons/grid.png");
        const list_icon = try Editor.getImGuiTexture("editor://icons/list.png");

        c.ImGui_Separator();
        {
            c.ImGui_BeginGroup();
            defer c.ImGui_EndGroup();

            const normal_col = c.ImGui_GetStyle().*.Colors[c.ImGuiCol_Button];
            const active_col = c.ImGui_GetStyle().*.Colors[c.ImGuiCol_ButtonHovered];
            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (edb.view_mode == .grid) active_col else normal_col,
            );
            if (c.ImGui_ImageButton("##grid_view", grid_icon, .{ .x = 24, .y = 24 })) {
                edb.view_mode = .grid;
            }
            c.ImGui_PopStyleColor();
            c.ImGui_SameLine();
            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (edb.view_mode == .list) active_col else normal_col,
            );
            if (c.ImGui_ImageButton("##list_view", list_icon, .{ .x = 24, .y = 24 })) {
                edb.view_mode = .list;
            }
            c.ImGui_PopStyleColor();
        }
    }

    {
        const open = c.ImGui_BeginChild(
            "gallery-frame",
            .{ .x = input_width + window_padding.x, .y = app_window_extent.y * 0.4 },
            0,
            0,
        );
        defer c.ImGui_EndChild();
        if (open) {
            const clicked = switch (edb.view_mode) {
                .list => self.drawList(),
                .grid => try self.drawGrid(),
            };

            if (c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_RootAndChildWindows)) {
                if (clicked or c.ImGui_IsKeyPressed(c.ImGuiKey_Enter) or c.ImGui_IsKeyPressed(c.ImGuiKey_KeypadEnter)) {
                    if (self.matches.items.len > 0) {
                        try self.use(&self.matches.items[self.selected]);
                    }
                }
            }
        }
    }
}

fn use(self: *Self, match: *const Match) !void {
    switch (match.entry.kind) {
        .filter => |filter| {
            const gop = try self.filters.getOrPut(filter.tag_name.span());
            if (gop.found_existing) return;
            gop.value_ptr.* = filter;
            try self.find_str.set("");
            self.request_focus = true;
            self.updateQueries();
        },
        .resource => |*resource| {
            self.on_pick.fire(.{resource});
            self.modal_callback.fire(.{resource});
            self.request_close = true;
        },
    }
}

fn onResourcesRegister(self: *Self, node: *const Resources.ResourceNode) void {
    self.indexResourceNode(node) catch |err| log.err("{}, Failed to index resource", .{err});
}

fn onResourcesUnregister(self: *Self, node: *const Resources.ResourceNode) void {
    _ = self;
    _ = node;
    log.warn("TODO:  unregister", .{});
}

fn onResourcesReinit(self: *Self) void {
    self.invalidateCaches(.{ .hard = true });
    self.indexFilterTags() catch |err| log.err("{}, Failed to index filters", .{err});
    (struct {
        fn f(this: *Self) !void {
            const root = try Resources.findResourceNode("/") orelse return error.NoResourceIndexed;
            for (root.children.values()) |*child| {
                try this.indexResourceNode(child);
            }
        }
    }).f(self) catch |err| log.err("{}, Failed to index resources", .{err});
}

fn indexFilterTags(self: *Self) !void {
    // file type filters
    inline for (@typeInfo(Resources.Resource.Type).Enum.fields) |ty| {
        const thumbnail = try iconThumbnail("editor://icons/filter.png");
        const gop = try self.index.getOrPut("File type: " ++ ty.name);

        if (!gop.found_existing) {
            gop.value_ptr.* = try self.allocator.create(Entry);
            gop.value_ptr.*.* = Entry{
                .kind = .{
                    .filter = filterByResourceType(@enumFromInt(ty.value)),
                },
                .thumbnail = thumbnail,
            };
        }
    }

    // protocols
    const root_resource = (try Resources.findResourceNode("/")).?;
    for (root_resource.children.values()) |*cat| {
        const protz = try self.allocator.dupeZ(u8, (try cat.node.uri()).protocolWithSeperator());
        errdefer self.allocator.free(protz);
        const gop = try self.index.getOrPut(protz);
        if (gop.found_existing) {
            self.allocator.free(protz);
            continue;
        }
        gop.value_ptr.* = try self.allocator.create(Entry);
        gop.value_ptr.*.* = Entry{
            .kind = .{
                .filter = .{
                    .tag_name = .{ .allocated = protz },
                    .predicate = &struct {
                        fn f(filter: *const Filter, it: *const Entry) bool {
                            return switch (it.kind) {
                                .resource => |r| std.mem.eql(u8, r.uri.protocolWithSeperator(), filter.tag_name.span()),
                                else => false,
                            };
                        }
                    }.f,
                    .user_data = .{ .void = {} },
                },
            },
            .thumbnail = try iconThumbnail("editor://icons/filter.png"),
        };
    }

    // asset type filters
    inline for (@typeInfo(assets.AssetType).Enum.fields) |ty| {
        const thumbnail = try iconThumbnail("editor://icons/filter.png");
        const gop = try self.index.getOrPut("Asset type: " ++ ty.name);

        if (!gop.found_existing) {
            gop.value_ptr.* = try self.allocator.create(Entry);
            gop.value_ptr.*.* = Entry{
                .kind = .{
                    .filter = filterByAssetType(@enumFromInt(ty.value)),
                },
                .thumbnail = thumbnail,
            };
        }
    }
}

fn indexResourceNode(self: *Self, node: *const Resources.ResourceNode) !void {
    self.invalidateCaches(.{});
    const uri = try node.node.uri();
    // if it is a protocol node, we should update our filters
    if (uri.parent() == null) {
        try self.indexFilterTags();
    }

    if (node.node == .resource) {
        try self.indexResource(node.node.resource);
    }

    for (node.children.values()) |*it| {
        try self.indexResourceNode(it);
    }
}

fn indexResource(self: *Self, id: Uuid) !void {
    var resource = try Resources.getResource(self.allocator, id) orelse return error.ResourceNotFound;
    errdefer resource.deinit(self.allocator);
    const gop = try self.index.getOrPut(resource.uri.spanZ());
    if (gop.found_existing) {
        resource.deinit(self.allocator);
        return;
    }

    var void_ = {};
    const thumbnail = Event(.{ *c.ImDrawList, *const Entry, Rect }).callback(void, &void_, struct {
        fn f(_: *void, drawlist: *c.ImDrawList, entry: *const Entry, rect: Rect) void {
            const ty = entry.kind.resource.type;
            const icon = Editor.getImGuiTexture(ty.fileIconUri()) catch return;
            c.ImDrawList_AddImage(
                drawlist,
                icon,
                .{ .x = rect.x, .y = rect.y },
                .{ .x = rect.x + rect.width, .y = rect.y + rect.height },
            );
        }
    }.f);

    gop.value_ptr.* = try self.allocator.create(Entry);
    gop.value_ptr.*.* = .{
        .kind = .{ .resource = resource },
        .thumbnail = thumbnail,
    };
}

fn calcContiguousBonus(ranges: []const Range) isize {
    if (ranges.len == 0) return 0;
    var best: isize = @intCast(ranges[0].end - ranges[0].start);
    var current: isize = best;
    var i: usize = 1;
    while (i < ranges.len) : (i += 1) {
        if (ranges[i].start == ranges[i - 1].end) {
            current += @intCast(ranges[i].end - ranges[i].start);
        } else {
            if (current > best) best = current;
            current = @intCast(ranges[i].end - ranges[i].start);
        }
    }
    if (current > best) best = current;
    return best;
}

fn updateQueries(self: *Self) void {
    self.invalidateCaches(.{});
    var iter = self.index.iterator();
    var ranges_buf: [4]Range = undefined;
    @memset(&ranges_buf, .{});
    const patt = self.find_str.span();
    query: while (iter.next()) |it| {
        const ranges = utils.approximateMatch(&ranges_buf, it.key_ptr.*, patt);
        if (ranges.len == 0) continue :query;
        for (self.filters.values()) |filter| {
            if (it.value_ptr.*.kind == .filter) {
                // Skip already used filters.
                if (std.mem.eql(u8, it.value_ptr.*.kind.filter.tag_name.span(), filter.tag_name.span())) {
                    continue :query;
                }
                break;
            } else if (filter.predicate(&filter, it.value_ptr.*)) {
                break;
            }
        } else if (self.filters.count() > 0) {
            continue :query;
        }
        const lev_score = utils.levenshtein(it.key_ptr.*, patt, self.allocator);
        const bonus = calcContiguousBonus(ranges);
        const score = @as(isize, @intCast(lev_score)) - (bonus * 2);

        self.matches.append(.{
            .score = score,
            .ranges = ranges_buf,
            .range_count = ranges.len,
            .key = it.key_ptr.*,
            .entry = it.value_ptr.*,
        }) catch {};
    }
    std.mem.sort(Match, self.matches.items, {}, struct {
        fn f(
            _: void,
            lhs: Match,
            rhs: Match,
        ) bool {
            return std.math.compare(lhs.score, .lt, rhs.score);
        }
    }.f);
    self.selected = @min(self.selected, @max(self.matches.items.len, 1) - 1);
}

fn invalidateCaches(self: *Self, comptime opts: struct { hard: bool = false }) void {
    if (opts.hard) {
        self.selected = 0;
        self.matches.clearAndFree();
    } else {
        self.matches.clearRetainingCapacity();
    }
}

fn drawList(self: *Self) bool {
    const avail = c.ImGui_GetContentRegionAvail();
    const padding = c.ImGui_GetStyle().*.FramePadding;
    const list_start_y = c.ImGui_GetCursorScreenPos().y;

    const total_entries: c_int = @intCast(self.matches.items.len);
    const row_height: f32 = 32;
    var clipper = c.ImGuiListClipper{};
    c.ImGuiListClipper_Begin(&clipper, total_entries, row_height);
    defer c.ImGuiListClipper_End(&clipper);
    var clicked: bool = false;
    while (c.ImGuiListClipper_Step(&clipper)) {
        var i: isize = clipper.DisplayStart;
        while (i < clipper.DisplayEnd) : (i += 1) {
            const index: usize = @intCast(i);
            const match = self.matches.items[index];
            c.ImGui_PushID(match.key);
            defer c.ImGui_PopID();

            const screen_pos = c.ImGui_GetCursorScreenPos();
            if (c.ImGui_BeginChildFrame(c.ImGui_GetID("item-frame"), .{ .x = avail.x, .y = row_height })) {
                { // draw the selectable region
                    const cursor = c.ImGui_GetCursorPos();
                    defer c.ImGui_SetCursorPos(cursor);
                    if (c.ImGui_SelectableEx(
                        "##item",
                        false,
                        if (self.selected == index)
                            c.ImGuiSelectableFlags_Highlight
                        else
                            c.ImGuiSelectableFlags_None,
                        .{ .x = avail.x, .y = row_height - padding.y * 2 },
                    )) {
                        self.selected = index;
                        clicked = true;
                    }
                }
                { // draw the thumbnail
                    const thumbnail_rect = Rect{
                        .x = screen_pos.x + padding.x,
                        .y = screen_pos.y + padding.y,
                        .width = 28,
                        .height = 28,
                    };
                    const child_drawlist = c.ImGui_GetWindowDrawList();
                    match.entry.thumbnail.call(.{ child_drawlist, match.entry, thumbnail_rect });
                }
                { // draw the highlightable label
                    const cursor = c.ImGui_GetCursorPos();
                    c.ImGui_SetCursorPosX(cursor.x + 32 + padding.x);
                    c.ImGui_SetCursorPosY(cursor.y + padding.y);
                    defer c.ImGui_SetCursorPosX(cursor.x);
                    imutils.drawTextWithHighlight(match.key, match.ranges[0..match.range_count], 0);
                }
            }
            c.ImGui_EndChildFrame();
        }
    }

    const dir = imutils.fourwayInputs();
    var force_scroll: bool = false;
    switch (dir) {
        .none, .left, .right => {},
        .up => {
            if (self.selected > 0) self.selected -= 1;
            force_scroll = true;
        },
        .down => {
            if (self.selected < self.matches.items.len - 1) {
                self.selected += 1;
            } else {
                self.selected = self.matches.items.len - 1;
            }
            force_scroll = true;
        },
    }

    if (force_scroll) {
        const current_scroll = c.ImGui_GetScrollY();
        const view_height = avail.y;

        const item_top = list_start_y + (@as(f32, @floatFromInt(self.selected))) * row_height;
        const item_bottom = item_top + row_height;

        if (dir == .down) {
            const visiblity_cutoff = list_start_y + current_scroll + view_height - row_height;
            if (item_bottom > visiblity_cutoff) {
                c.ImGui_SetScrollY(current_scroll + (item_bottom - visiblity_cutoff));
            }
        } else if (dir == .up) {
            if (item_top < list_start_y + current_scroll) {
                c.ImGui_SetScrollY(current_scroll - ((list_start_y + current_scroll) - item_top));
            }
        }
    }

    return clicked;
}

fn drawGrid(self: *Self) !bool {
    const grid_start_y = c.ImGui_GetCursorScreenPos().y;
    const avail = c.ImGui_GetContentRegionAvail();
    const style = c.ImGui_GetStyle().*;
    const padding = style.FramePadding;
    const total_entries: usize = self.matches.items.len;

    const columns: usize = 5;

    const effective_avail_x: f32 = avail.x - style.ScrollbarSize;
    const cell_width: f32 = effective_avail_x / columns;

    const row_count: usize = (total_entries + columns - 1) / columns;
    var sfa = std.heap.stackFallback(2048, self.allocator);
    const allocator = sfa.get();
    var row_heights = try allocator.alloc(f32, row_count);
    defer allocator.free(row_heights);

    var clicked = false;
    var row: usize = 0;
    while (row < row_count) : (row += 1) {
        const row_start = row * columns;
        const row_end = if (row_start + columns < total_entries)
            row_start + columns
        else
            total_entries;

        var row_max_height: f32 = 0;
        {
            var i: usize = row_start;
            while (i < row_end) : (i += 1) {
                const match = self.matches.items[i];
                const icon_size: f32 = cell_width - 2 * padding.x;
                const text_avail: f32 = cell_width - 2 * padding.x;
                const text_size = c.ImGui_CalcTextSizeEx(match.key, null, false, text_avail);
                const cell_req_height = padding.y + icon_size + 4 + text_size.y + padding.y;
                if (cell_req_height > row_max_height) row_max_height = cell_req_height;
            }
        }
        row_heights[row] = row_max_height;

        c.ImGui_BeginGroup();
        {
            var col: usize = 0;
            while (col < columns) : (col += 1) {
                const index = row * columns + col;
                if (index >= total_entries) break;
                const match = self.matches.items[index];

                c.ImGui_PushID(match.key);
                if (c.ImGui_BeginChildFrameEx(
                    c.ImGui_GetID("grid_cell"),
                    .{ .x = cell_width, .y = row_max_height },
                    c.ImGuiWindowFlags_NoScrollbar | c.ImGuiWindowFlags_NoScrollWithMouse,
                )) {
                    { // draw the selectable region
                        const cursor = c.ImGui_GetCursorPos();
                        defer c.ImGui_SetCursorPos(cursor);
                        if (c.ImGui_SelectableEx(
                            "##item",
                            false,
                            if (self.selected == index)
                                c.ImGuiSelectableFlags_Highlight
                            else
                                c.ImGuiSelectableFlags_None,
                            .{ .x = cell_width, .y = row_max_height },
                        )) {
                            self.selected = index;
                            clicked = true;
                        }
                    }
                    { // draw the thumbnail
                        const cell_pos = c.ImGui_GetCursorScreenPos();
                        const icon_size: f32 = cell_width - 2 * padding.x;
                        const icon_rect = Rect{
                            .x = cell_pos.x + (cell_width - icon_size) * 0.5,
                            .y = cell_pos.y + padding.y,
                            .width = icon_size,
                            .height = icon_size,
                        };

                        const cell_drawlist = c.ImGui_GetWindowDrawList();
                        match.entry.thumbnail.call(.{ cell_drawlist, match.entry, icon_rect });
                    }
                    { // draw the highlighted label
                        const res_text = match.key;
                        const text_avail: f32 = cell_width - 2 * padding.x;
                        const wrapped_text_size = c.ImGui_CalcTextSizeEx(res_text, null, false, text_avail);
                        c.ImGui_SetCursorPosY(row_max_height - padding.y - wrapped_text_size.y);
                        c.ImGui_SetCursorPosX((cell_width - wrapped_text_size.x) * 0.5);
                        imutils.drawTextWithHighlight(res_text, match.ranges[0..match.range_count], text_avail);
                    }
                }
                c.ImGui_EndChildFrame();
                c.ImGui_PopID();

                if (col < columns - 1) {
                    c.ImGui_SameLine();
                }
            }
        }
        c.ImGui_EndGroup();
        c.ImGui_Spacing();
    }
    c.ImGui_Dummy(.{ .x = 0, .y = padding.y });

    // ---- Grid navigation via fourway input ----
    const input = imutils.fourwayInputs();
    var new_selected: usize = self.selected;
    const current_row: usize = self.selected / columns;
    const current_col: usize = self.selected % columns;

    switch (input) {
        .left => {
            if (current_col > 0) {
                new_selected = current_row * columns + (current_col - 1);
            }
        },
        .right => {
            if (current_col < columns - 1) {
                const candidate = current_row * columns + (current_col + 1);
                if (candidate < total_entries) {
                    new_selected = candidate;
                }
            }
        },
        .up => {
            if (current_row > 0) {
                const candidate = (current_row - 1) * columns + current_col;
                if (candidate < total_entries) {
                    new_selected = candidate;
                }
            }
        },
        .down => {
            if (current_row < ((total_entries + columns - 1) / columns) - 1) {
                const candidate = (current_row + 1) * columns + current_col;
                new_selected = @min(candidate, total_entries - 1);
            }
        },
        else => {},
    }
    self.selected = new_selected;

    // -- Vertical Scroll Snapping --
    if (self.matches.items.len > 0) {
        const sel_row = self.selected / columns;
        var sel_row_offset: f32 = 0;
        {
            var r_idx: usize = 0;
            while (r_idx < sel_row) : (r_idx += 1) {
                sel_row_offset += row_heights[r_idx] + style.ItemSpacing.y;
            }
        }
        const sel_row_height: f32 = row_heights[sel_row];

        const current_scroll = c.ImGui_GetScrollY();
        const view_height = avail.y;
        const sel_row_top = grid_start_y + sel_row_offset;
        const sel_row_bottom = sel_row_top + sel_row_height;

        if (input == .down) {
            if (sel_row_bottom > grid_start_y + current_scroll + view_height) {
                c.ImGui_SetScrollY(current_scroll + (sel_row_bottom - (grid_start_y + current_scroll + view_height)));
            }
        } else if (input == .up) {
            if (sel_row_top < grid_start_y + current_scroll) {
                c.ImGui_SetScrollY(current_scroll - ((grid_start_y + current_scroll) - sel_row_top));
            }
        }
    }
    return clicked;
}

pub fn drawTagsGrid(locked_tags: [][:0]const u8, tags: [][:0]const u8, max_width: f32, avail_height: f32) !struct { width: f32, clicked_index: ?usize } {
    if (locked_tags.len == 0 and tags.len == 0) return .{ .width = 0, .clicked_index = null };

    const style = c.ImGui_GetStyle().*;
    const padh: f32 = style.FramePadding.x;
    const padv: f32 = style.FramePadding.y;
    const spacing: f32 = style.ItemSpacing.x;

    // --- First Pass: Layout Simulation ---
    var row_count: usize = 1;
    var current_row: usize = 0;
    var current_x: f32 = 0;
    var row_heights: [64]f32 = undefined;
    var max_x: f32 = 0;
    row_heights[0] = 0;

    const Calc = struct {
        spacing: f32,
        max_width: f32,
        padh: f32,
        padv: f32,
        row_heights: *[64]f32,
        row_count: *usize,
        current_row: *usize,
        current_x: *f32,
        max_x: *f32,
        fn calc(o: @This(), tt: [][:0]const u8, lock: bool) !void {
            for (tt) |tag| {
                var tag_buf: [128]u8 = undefined;
                const display_label = if (lock) try std.fmt.bufPrintZ(&tag_buf, " {s}", .{tag}) else tag;
                const text_size = c.ImGui_CalcTextSize(display_label);
                const pill_width = text_size.x + 2 * o.padh;
                const pill_height = text_size.y + 2 * o.padv;

                if (pill_height > o.row_heights[o.current_row.*]) {
                    o.row_heights.*[o.current_row.*] = pill_height;
                }
                if (o.current_x.* + pill_width > o.max_width and o.current_x.* > 0) {
                    o.row_count.* += 1;
                    o.current_row.* += 1;
                    o.row_heights[o.current_row.*] = pill_height;
                    o.current_x.* = pill_width + o.spacing;
                } else {
                    o.current_x.* += pill_width + o.spacing;
                }

                o.max_x.* = @max(o.max_x.*, o.current_x.*);
            }
        }
    };

    const calculator = Calc{
        .spacing = spacing,
        .max_width = max_width,
        .padh = padh,
        .padv = padv,
        .row_heights = &row_heights,
        .row_count = &row_count,
        .current_row = &current_row,
        .current_x = &current_x,
        .max_x = &max_x,
    };
    try calculator.calc(locked_tags, true);
    try calculator.calc(tags, false);

    var vertical_offset: f32 = 0;
    if (row_count == 1) {
        vertical_offset = (avail_height - row_heights[0]) * 0.5;
    }

    // --- Second Pass: Render the Pills ---
    var clicked_index: ?usize = null;
    {
        _ = c.ImGui_BeginChild("tags_region", .{ .x = max_x, .y = avail_height }, 0, c.ImGuiWindowFlags_NoBackground);
        defer c.ImGui_EndChild();

        current_x = 0;
        current_row = 0;
        const start_pos = c.ImGui_GetCursorPos();
        var current_y: f32 = 0;

        const Render = struct {
            row_heights: []const f32,
            max_width: f32,
            padh: f32,
            spacing: f32,
            vertical_offset: f32,
            start_pos: c.ImVec2,
            current_x: *f32,
            current_y: *f32,
            current_row: *usize,
            clicked_index: *?usize,

            fn render(o: @This(), tt: [][:0]const u8, lock: bool) !void {
                for (tt, 0..) |tag, i| {
                    var tag_buf: [128]u8 = undefined;
                    const display_label = if (lock) try std.fmt.bufPrintZ(&tag_buf, " {s}", .{tag}) else tag;
                    const text_size = c.ImGui_CalcTextSize(display_label);
                    const pill_width = text_size.x + 2 * o.padh;

                    if (o.current_x.* + pill_width > o.max_width and o.current_x.* > 0) {
                        o.current_y.* += o.row_heights[o.current_row.*] + o.spacing;
                        o.current_row.* += 1;
                        o.current_x.* = 0;
                    }
                    var pos: c.ImVec2 = o.start_pos;
                    pos.x += o.current_x.*;
                    pos.y += o.current_y.* + o.vertical_offset;
                    c.ImGui_SetCursorPos(pos);
                    if (c.ImGui_Button(display_label)) {
                        o.clicked_index.* = i;
                    }

                    o.current_x.* += pill_width + o.spacing;
                }
            }
        };

        const renderer = Render{
            .row_heights = &row_heights,
            .max_width = max_width,
            .padh = padh,
            .spacing = spacing,
            .vertical_offset = vertical_offset,
            .start_pos = start_pos,
            .current_x = &current_x,
            .current_y = &current_y,
            .current_row = &current_row,
            .clicked_index = &clicked_index,
        };
        try renderer.render(locked_tags, true);
        clicked_index = null; // ignore any clicks on the locked tags
        try renderer.render(tags, false);
        c.ImGui_SetCursorPos(.{ .x = start_pos.x + max_x, .y = start_pos.y });
    }

    return .{
        .width = max_x,
        .clicked_index = clicked_index,
    };
}

const Entry = struct {
    const Kind = union(enum) {
        filter: Filter,
        resource: Resources.Resource,

        fn deinit(kind: *Kind, allocator: std.mem.Allocator) void {
            switch (kind.*) {
                .resource => kind.resource.deinit(allocator),
                .filter => kind.filter.deinit(allocator),
            }
        }

        pub fn eql(lhs: *const Kind, rhs: *const Kind) bool {
            if (std.meta.activeTag(lhs.*) != std.meta.activeTag(rhs.*)) return false;
            return switch (lhs.*) {
                .filter => |it| it.eql(&rhs.filter),
                .resource => |it| it.eql(&rhs.resource),
            };
        }
    };

    const Thumbnail = Event(.{ *c.ImDrawList, *const Entry, Rect });

    kind: Kind,
    thumbnail: Thumbnail.Callback,

    pub fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
        self.kind.deinit(allocator);
    }
};

const Match = struct {
    score: isize,
    ranges: [4]Range,
    range_count: usize,
    key: [:0]const u8,
    entry: *const Entry,
};

pub const Selector = union(enum) {
    filter: []const u8,
    resource: Uuid,
};

pub const Filter = struct {
    tag_name: union(enum) {
        constant: [:0]const u8,
        allocated: [:0]u8,

        pub fn deinit(str: @This(), allocator: std.mem.Allocator) void {
            return switch (str) {
                .allocated => |s| allocator.free(s),
                .constant => {},
            };
        }

        pub fn span(str: @This()) [:0]const u8 {
            return switch (str) {
                inline .constant, .allocated => |s| s,
            };
        }
    },
    predicate: *const fn (*const Filter, *const Entry) bool,
    user_data: union {
        void: void,
        ptr: *anyopaque,
        int: isize,
    },

    pub fn deinit(filter: *@This(), allocator: std.mem.Allocator) void {
        filter.tag_name.deinit(allocator);
    }

    pub fn eql(lhs: *const Filter, rhs: *const Filter) bool {
        return std.mem.eql(u8, lhs.tag_name.span(), rhs.tag_name.span()) and lhs.predicate == rhs.predicate;
    }
};

pub fn filterByResourceType(ty: Resources.Resource.Type) Filter {
    const tag_name: [:0]const u8 = switch (ty) {
        .unknown => "Unknown File Type",
        .project => "Project File",
        .scene => ".scene",
        .shader_stage => ".frag/.vert",
        .shader => ".shader",
        .mat => ".mat",
        .obj => ".obj",
        .fbx => ".fbx",
        .png => ".png",
    };

    return .{
        .tag_name = .{
            .constant = tag_name,
        },
        .predicate = &struct {
            fn pred(f: *const Filter, it: *const Entry) bool {
                return switch (it.kind) {
                    .resource => |r| @intFromEnum(r.type) == f.user_data.int,
                    else => false,
                };
            }
        }.pred,
        .user_data = .{ .int = @intFromEnum(ty) },
    };
}

pub fn filterByAssetType(ty: assets.AssetType) Filter {
    return .{
        .tag_name = .{ .constant = @tagName(ty) },
        .predicate = &struct {
            fn pred(f: *const Filter, it: *const Entry) bool {
                const t: assets.AssetType = @enumFromInt(f.user_data.int);
                return switch (it.kind) {
                    .resource => |r| r.type.toAssetType() == t or
                        (t == .texture and r.type.toAssetType() == .image),
                    else => false,
                };
            }
        }.pred,
        .user_data = .{ .int = @intFromEnum(ty) },
    };
}

fn iconThumbnail(uri: []const u8) !Entry.Thumbnail.Callback {
    const icon = try Editor.getImGuiTexture(uri);
    // imgui's ImTextureID is just a pointer to the derscriptor set
    return Entry.Thumbnail.callback(anyopaque, @ptrFromInt(icon), struct {
        fn f(icon_: *anyopaque, drawlist: *c.ImDrawList, _: *const Entry, rect: Rect) void {
            c.ImDrawList_AddImage(
                drawlist,
                @intFromPtr(icon_),
                .{ .x = rect.x, .y = rect.y },
                .{ .x = rect.x + rect.width, .y = rect.y + rect.height },
            );
        }
    }.f);
}
