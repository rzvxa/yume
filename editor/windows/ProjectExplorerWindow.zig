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

find_str: imutils.ImString,

index: collections.StringSentinelArrayHashMap(0, Entry),
matches: std.ArrayList(Match),

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .find_str = try imutils.ImString.init(allocator),
        .index = collections.StringSentinelArrayHashMap(0, Entry).init(allocator),
        .matches = std.ArrayList(Match).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.find_str.deinit();

    Resources.onRegister().remove(Resources.OnRegisterEvent.callback(Self, self, &Self.onResourcesRegister)) catch {};
    Resources.onUnregister().remove(Resources.OnUnregisterEvent.callback(Self, self, &Self.onResourcesUnregister)) catch {};
    Resources.onReinit().remove(Resources.OnReinitEvent.callback(Self, self, &Self.onResourcesReinit)) catch {};

    self.invalidateCaches(.{ .hard = true });
    {
        defer self.index.deinit();
        var values = self.index.values();
        for (values, 0..) |it, i| {
            switch (it.kind) {
                .resource => values[i].kind.resource.deinit(self.allocator),
            }
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
        input_height + app_window_extent.y * 0.4
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
            .x = self.anim_window_width + window_padding.x - 2,
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
                c.ImGuiWindowFlags_NoTitleBar |
                c.ImGuiWindowFlags_NoCollapse,
        )) {
            return;
        }
    }
    defer self.first_draw = false;
    defer c.ImGui_EndPopup();

    {
        c.ImGui_PushFont(Editor.roboto24);
        defer c.ImGui_PopFont();
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
        if (self.first_draw) {
            c.ImGui_SetKeyboardFocusHere();
        }
        if (c.ImGui_InputTextWithHintAndSizeEx(
            "##find-query",
            "Start typing...",
            self.find_str.buf,
            @intCast(self.find_str.size()),
            .{ .x = input_width - 8 - input_height, .y = input_height - 8 },
            c.ImGuiInputTextFlags_CallbackResize | c.ImGuiInputTextFlags_AutoSelectAll,
            &imutils.ImString.InputTextCallback,
            &self.find_str,
        )) {
            self.updateQueries();
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
            .{ .x = input_width, .y = app_window_extent.y * 0.4 },
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
    (struct {
        fn f(this: *Self) !void {
            const root = try Resources.findResourceNode("/") orelse return error.NoResourceIndexed;
            try this.indexResourceNode(root);
        }
    }).f(self) catch |err| log.err("{}, Failed to index resources", .{err});
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
    const preview = Event(.{ *c.ImDrawList, *const Entry, Rect }).callback(void, &void_, struct {
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

    try self.index.put(resource.uri.spanZ(), .{ .kind = .{ .resource = resource }, .preview = preview });
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
        self.matches.append(.{ .score = score, .ranges = ranges_buf, .entry = it.value_ptr }) catch {};
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

            c.ImGui_PushID(&match.entry.kind.resource.id.urnZ());
            const screen_pos = c.ImGui_GetCursorScreenPos();
            if (c.ImGui_BeginChildFrame(c.ImGui_GetID("preview"), .{ .x = avail.x, .y = row_height })) {
                const rect = Rect{
                    .x = screen_pos.x + padding.x,
                    .y = screen_pos.y + padding.y,
                    .width = 28,
                    .height = 28,
                };
                c.ImGui_SetCursorPosX(c.ImGui_GetCursorPos().x + 32 + padding.x);
                _ = c.ImGui_Button(match.entry.kind.resource.path());
                const child_drawlist = c.ImGui_GetWindowDrawList();
                match.entry.preview.call(.{ child_drawlist, match.entry, rect });
            }
            c.ImGui_EndChildFrame();
            c.ImGui_PopID();
        }
    }
    c.ImGuiListClipper_End(&clipper);
}

fn drawGrid(self: *Self) void {
    const avail = c.ImGui_GetContentRegionAvail();
    const padding = c.ImGui_GetStyle().*.FramePadding;
    const total_entries: usize = self.matches.items.len;

    // Set a fixed cell size. Adjust cell_width as needed.
    const cell_width: f32 = 128;
    const cell_height: f32 = 32;
    // Compute how many columns fit in the available space.
    const col_count: usize = @max(1, @as(usize, @intFromFloat(avail.x / cell_width)));
    // Compute the necessary number of rows (rounding up).
    const row_count: usize = (total_entries + col_count - 1) / col_count;

    var clipper = c.ImGuiListClipper{};
    c.ImGuiListClipper_Begin(&clipper, @intCast(row_count), cell_height);
    while (c.ImGuiListClipper_Step(&clipper)) {
        // Set the cursor position for the start of the visible row.
        // (Optional: if you want the clipper to auto-adjust, this call may not be needed.)
        c.ImGui_SetCursorPosY(clipper.StartPosY);

        var row: isize = clipper.DisplayStart;
        while (row < clipper.DisplayEnd) : (row += 1) {
            c.ImGui_BeginGroup(); // Begin a horizontal grouping for this row

            var col: usize = 0;
            while (col < col_count) : (col += 1) {
                const index = @as(usize, @intCast(row)) * col_count + col;
                if (index >= total_entries) break;
                const match = self.matches.items[index];

                c.ImGui_PushID(&match.entry.kind.resource.id.urnZ());

                // Get the screen position for the cell.
                const cell_screen_pos = c.ImGui_GetCursorScreenPos();
                // Create a preview rect using the screen position and padding.
                const rect = Rect{
                    .x = cell_screen_pos.x + padding.x,
                    .y = cell_screen_pos.y + padding.y,
                    .width = 28,
                    .height = 28,
                };

                // Render the preview image.
                const cell_drawlist = c.ImGui_GetWindowDrawList();
                match.entry.preview.call(.{ cell_drawlist, match.entry, rect });

                // Offset the cursor within the cell so that the button appears to the right of the preview.
                c.ImGui_SameLine();
                _ = c.ImGui_Button(match.entry.kind.resource.path());

                c.ImGui_PopID();

                // Force a fixed cell width by inserting spacing if this isn’t the last column.
                if (col < col_count - 1) {
                    c.ImGui_SameLine();
                    // Optional: You could call ImGui_Spacing() if you’d like extra space.
                }
            }
            c.ImGui_EndGroup();

            // Advance cursor to the next row.
            // If not the last visible row, add vertical spacing.
            if (row < clipper.DisplayEnd - 1) {
                c.ImGui_Spacing();
            }
        }
    }
    c.ImGuiListClipper_End(&clipper);
}

const Kind = union(enum) {
    resource: Resources.Resource,
};

const Entry = struct {
    kind: Kind,
    preview: Event(.{ *c.ImDrawList, *const Entry, Rect }).Callback,
};

const Match = struct {
    score: usize,
    ranges: [4]Range,
    entry: *const Entry,
};
