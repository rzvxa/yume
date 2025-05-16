const c = @import("clibs");
const std = @import("std");

const Uuid = @import("yume").Uuid;
const GameApp = @import("yume").GameApp;
const ecs = @import("yume").ecs;
const utils = @import("yume").utils;
const Rect = @import("yume").Rect;
const Event = @import("yume").Event;
const collections = @import("yume").collections;

const Editor = @import("../Editor.zig");
const Resources = @import("../Resources.zig");
const imutils = @import("../imutils.zig");

const Range = utils.Range;
const lerp = std.math.lerp;

const log = std.log.scoped(.ProjectExplorer);

const Self = @This();

allocator: std.mem.Allocator,
visible: bool = false,
first_draw: bool = true,

anim_alpha: f32 = 0,
anim_window_height: f32 = 0,
anim_window_width: f32 = 0,

view_mode: enum { list, grid } = .list,

filters: collections.StringSentinelArrayHashMap(0, Filter),

find_str: imutils.ImString,

index: collections.StringSentinelArrayHashMap(0, Entry),
matches: std.ArrayList(Match),

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .filters = collections.StringSentinelArrayHashMap(0, Filter).init(allocator),
        .find_str = try imutils.ImString.init(allocator),
        .index = collections.StringSentinelArrayHashMap(0, Entry).init(allocator),
        .matches = std.ArrayList(Match).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.filters.deinit();
    self.find_str.deinit();

    Resources.onRegister().remove(Resources.OnRegisterEvent.callback(Self, self, &Self.onResourcesRegister)) catch {};
    Resources.onUnregister().remove(Resources.OnUnregisterEvent.callback(Self, self, &Self.onResourcesUnregister)) catch {};
    Resources.onReinit().remove(Resources.OnReinitEvent.callback(Self, self, &Self.onResourcesReinit)) catch {};

    self.invalidateCaches(.{ .hard = true });
    {
        defer self.index.deinit();
        var values = self.index.values();
        for (0..values.len) |i| {
            values[i].kind.deinit(self.allocator);
        }
    }
}

pub fn setup(self: *Self) !void {
    self.onResourcesReinit();

    try Resources.onRegister().append(Resources.OnRegisterEvent.callback(Self, self, &Self.onResourcesRegister));
    try Resources.onUnregister().append(Resources.OnUnregisterEvent.callback(Self, self, &Self.onResourcesUnregister));
    try Resources.onReinit().append(Resources.OnReinitEvent.callback(Self, self, &Self.onResourcesReinit));
}

pub fn draw(self: *Self, ctx: *GameApp) !void {
    if (!self.visible and
        c.ImGui_IsKeyDown(c.ImGuiKey_ModCtrl) and
        c.ImGui_IsKeyPressed(c.ImGuiKey_P))
    {
        self.visible = true;
        self.first_draw = true;
        c.ImGui_OpenPopup("Project Explorer", 0);
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
            return;
        }
        c.ImGui_SetScrollY(0);
    }
    defer self.first_draw = false;
    defer c.ImGui_EndPopup();

    {
        c.ImGui_PushStyleColorImVec4(
            c.ImGuiCol_FrameBg,
            std.mem.zeroes(c.ImVec4),
        );
        defer c.ImGui_PopStyleColor();
        c.ImGui_Image(try Editor.getImGuiTexture("editor://icons/search.png"), .{ .x = input_height - 8, .y = input_height - 8 });
        c.ImGui_SetItemTooltip(
            \\ e.g. "material,mesh: barrel" finds all materials and meshes with barrel in their path
        );
        c.ImGui_SameLine();
        const drawn_tags = try drawTagsGrid(self.filters.keys(), @divTrunc(input_width, 3), input_height - 8);
        if (drawn_tags.clicked_index) |clicked| {
            self.filters.orderedRemoveAt(clicked);
        }

        c.ImGui_SameLine();
        {
            c.ImGui_PushFont(Editor.roboto24);
            defer c.ImGui_PopFont();
            if (self.first_draw) {
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
            }
        }
    }

    if (self.find_str.length() == 0) {
        return;
    }

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
                if (self.view_mode == .grid) active_col else normal_col,
            );
            if (c.ImGui_ImageButton("##grid_view", grid_icon, .{ .x = 24, .y = 24 })) {
                self.view_mode = .grid;
            }
            c.ImGui_PopStyleColor();
            c.ImGui_SameLine();
            c.ImGui_PushStyleColorImVec4(
                c.ImGuiCol_Button,
                if (self.view_mode == .list) active_col else normal_col,
            );
            if (c.ImGui_ImageButton("##list_view", list_icon, .{ .x = 24, .y = 24 })) {
                self.view_mode = .list;
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
            switch (self.view_mode) {
                .list => self.drawList(),
                .grid => self.drawGrid(),
            }
        }
    }
}

fn onResourcesRegister(self: *Self, res: *const Resources.Resource, node: *const Resources.ResourceNode) void {
    _ = self;
    _ = node;
    log.debug("HERE: {s}", .{res.path()});
}

fn onResourcesUnregister(self: *Self, res: *const Resources.Resource, node: *const Resources.ResourceNode) void {
    _ = self;
    _ = node;
    log.debug("HERE: {s}", .{res.path()});
}

fn onResourcesReinit(self: *Self) void {
    self.invalidateCaches(.{ .hard = true });
    self.indexFilterTags() catch |err| log.err("{}, Failed to index filters", .{err});
    (struct {
        fn f(this: *Self) !void {
            const root = try Resources.findResourceNode("/") orelse return error.NoResourceIndexed;
            try this.indexResourceNode(root);
        }
    }).f(self) catch |err| log.err("{}, Failed to index resources", .{err});
}

fn indexFilterTags(self: *Self) !void {
    const types = @typeInfo(Resources.Resource.Type).Enum.fields;
    inline for (types) |ty| {
        const entry = Entry{
            .kind = .{
                .filter = .{
                    .tag_name = ty.name,
                    .predicate = &struct {
                        fn f(it: *const Entry) bool {
                            return switch (it.kind) {
                                .resource => |r| @intFromEnum(r.type) == ty.value,
                                else => false,
                            };
                        }
                    }.f,
                },
            },
            .thumbnail = thumbnail: {
                var void_ = {};
                break :thumbnail Event(.{ *c.ImDrawList, *const Entry, Rect }).callback(void, &void_, struct {
                    fn f(_: *void, drawlist: *c.ImDrawList, _: *const Entry, rect: Rect) void {
                        const icon = Editor.getImGuiTexture("editor://icons/filter.png") catch return;
                        c.ImDrawList_AddImage(
                            drawlist,
                            icon,
                            .{ .x = rect.x, .y = rect.y },
                            .{ .x = rect.x + rect.width, .y = rect.y + rect.height },
                        );
                    }
                }.f);
            },
        };
        try self.index.put(
            "Filter by \"" ++ ty.name ++ "\"",
            entry,
        );
    }
}

fn indexResourceNode(self: *Self, node: *const Resources.ResourceNode) !void {
    self.invalidateCaches(.{});
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
    if (self.index.contains(resource.uri.spanZ())) {
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

    try self.index.put(resource.uri.spanZ(), .{ .kind = .{ .resource = resource }, .thumbnail = thumbnail });
}

fn updateQueries(self: *Self) void {
    self.invalidateCaches(.{});
    var iter = self.index.iterator();
    var ranges_buf: [4]Range = undefined;
    @memset(&ranges_buf, .{});
    const patt = self.find_str.span();
    while (iter.next()) |it| {
        const ranges = utils.approximateMatch(&ranges_buf, it.key_ptr.*, patt);
        if (ranges.len == 0) continue;

        const score = utils.levenshtein(it.key_ptr.*, patt, self.allocator);
        self.matches.append(.{
            .score = score,
            .ranges = ranges_buf,
            .range_count = ranges.len,
            .key = it.key_ptr.*,
            .entry = it.value_ptr,
        }) catch {};
    }
}

fn invalidateCaches(self: *Self, comptime opts: struct { hard: bool = false }) void {
    if (opts.hard) {
        self.matches.clearAndFree();
    } else {
        self.matches.clearRetainingCapacity();
    }
}

fn drawList(self: *Self) void {
    const avail = c.ImGui_GetContentRegionAvail();
    const padding = c.ImGui_GetStyle().*.FramePadding;

    const total_entries: c_int = @intCast(self.matches.items.len);
    const row_height: f32 = 32;
    var clipper = c.ImGuiListClipper{};
    c.ImGuiListClipper_Begin(&clipper, total_entries, row_height);
    while (c.ImGuiListClipper_Step(&clipper)) {
        var i: isize = clipper.DisplayStart;
        while (i < clipper.DisplayEnd) : (i += 1) {
            const match = self.matches.items[@intCast(i)];
            c.ImGui_PushID(match.key);
            defer c.ImGui_PopID();

            const screen_pos = c.ImGui_GetCursorScreenPos();
            if (c.ImGui_BeginChildFrame(c.ImGui_GetID("item-frame"), .{ .x = avail.x, .y = row_height })) {
                { // draw the selectable region
                    const cursor = c.ImGui_GetCursorPos();
                    defer c.ImGui_SetCursorPos(cursor);
                    _ = c.ImGui_SelectableEx("##item", false, 0, .{ .x = avail.x, .y = row_height - padding.y * 2 });
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
    c.ImGuiListClipper_End(&clipper);
}

fn drawGrid(self: *Self) void {
    const avail = c.ImGui_GetContentRegionAvail();
    const style = c.ImGui_GetStyle().*;
    const padding = style.FramePadding;
    const total_entries: usize = self.matches.items.len;

    const columns: usize = 5;

    const effective_avail_x: f32 = avail.x - style.ScrollbarSize;
    const cell_width: f32 = effective_avail_x / columns;

    const row_count: usize = (total_entries + columns - 1) / columns;

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
                        _ = c.ImGui_SelectableEx("##item", false, 0, .{ .x = cell_width, .y = row_max_height });
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
}

const Kind = union(enum) {
    filter: Filter,
    resource: Resources.Resource,

    fn deinit(kind: *Kind, allocator: std.mem.Allocator) void {
        switch (kind.*) {
            .resource => kind.resource.deinit(allocator),
            .filter => {},
        }
    }
};

const Entry = struct {
    kind: Kind,
    thumbnail: Event(.{ *c.ImDrawList, *const Entry, Rect }).Callback,
};

const Match = struct {
    score: usize,
    ranges: [4]Range,
    range_count: usize,
    key: [:0]const u8,
    entry: *const Entry,
};

const Filter = struct {
    tag_name: [:0]const u8,
    predicate: *const fn (*const Entry) bool,
};

pub fn drawTagsGrid(tags: [][:0]const u8, max_width: f32, avail_height: f32) !struct { width: f32, clicked_index: ?usize } {
    const style = c.ImGui_GetStyle().*;
    const padh: f32 = 4;
    const padv: f32 = 4;
    const spacing: f32 = style.ItemSpacing.x;

    // --- First Pass: Layout Simulation ---
    var row_count: usize = 1;
    var current_row: usize = 0;
    var current_x: f32 = 0;
    var row_heights: [64]f32 = undefined;
    row_heights[0] = 0;

    for (tags) |tag| {
        const text_size = c.ImGui_CalcTextSize(tag);
        const pill_width = text_size.x + 2 * padh;
        const pill_height = text_size.y + 2 * padv;

        if (pill_height > row_heights[current_row]) {
            row_heights[current_row] = pill_height;
        }
        if (current_x + pill_width > max_width and current_x > 0) {
            row_count += 1;
            current_row += 1;
            row_heights[current_row] = pill_height;
            current_x = pill_width + spacing;
        } else {
            current_x += pill_width + spacing;
        }
    }

    var verticalOffset: f32 = 0;
    if (row_count == 1) {
        verticalOffset = (avail_height - row_heights[0]) * 0.5;
    }

    // --- Second Pass: Render the Pills ---
    const startPos = c.ImGui_GetCursorPos();
    current_x = 0;
    current_row = 0;
    var currentY: f32 = 0;
    var clicked_index: ?usize = null;
    for (tags, 0..) |tag, i| {
        const text_size = c.ImGui_CalcTextSize(tag);
        const pill_width = text_size.x + 2 * padh;

        if (current_x + pill_width > max_width and current_x > 0) {
            currentY += row_heights[current_row] + spacing;
            current_row += 1;
            current_x = 0;
        }
        var pos: c.ImVec2 = startPos;
        pos.x += current_x;
        pos.y += currentY + verticalOffset;
        c.ImGui_SetCursorPos(pos);
        if (c.ImGui_Button(tag)) {
            clicked_index = i;
        }

        current_x += pill_width + spacing;
    }

    return .{
        .width = current_x,
        .clicked_index = clicked_index,
    };
}
