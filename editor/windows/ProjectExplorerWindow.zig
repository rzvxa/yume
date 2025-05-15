const c = @import("clibs");
const std = @import("std");

const Uuid = @import("yume").Uuid;
const GameApp = @import("yume").GameApp;
const ecs = @import("yume").ecs;
const utils = @import("yume").utils;
const Event = @import("yume").Event;
const collections = @import("yume").collections;

const Editor = @import("../Editor.zig");
const Resources = @import("../Resources.zig");
const imutils = @import("../imutils.zig");

const log = std.log.scoped(.ProjectExplorer);

const Self = @This();

allocator: std.mem.Allocator,
visible: bool = false,
first_draw: bool = true,

find_str: imutils.ImString,

index: collections.StringSentinelArrayHashMap(0, Entry),

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .find_str = try imutils.ImString.init(allocator),
        .index = collections.StringSentinelArrayHashMap(0, Entry).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.find_str.deinit();

    Resources.onRegister().remove(Resources.OnRegisterEvent.callback(Self, self, &Self.onResourcesRegister)) catch {};
    Resources.onUnregister().remove(Resources.OnUnregisterEvent.callback(Self, self, &Self.onResourcesUnregister)) catch {};
    Resources.onReinit().remove(Resources.OnReinitEvent.callback(Self, self, &Self.onResourcesReinit)) catch {};

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
    if (!self.visible and c.ImGui_IsKeyDown(c.ImGuiKey_ModCtrl) and c.ImGui_IsKeyPressed(c.ImGuiKey_P)) {
        self.visible = true;
        self.first_draw = true;
        c.ImGui_OpenPopup("Project Explorer", 0);
    }

    const app_window_extent = ctx.windowExtent().toVec2();
    const input_width = @min(800, app_window_extent.x * 0.4);
    {
        c.ImGui_SetNextWindowPos(.{ .x = app_window_extent.x / 2 - input_width / 2, .y = app_window_extent.y * 0.2 }, c.ImGuiCond_Appearing);
        c.ImGui_SetNextWindowSize(.{ .x = input_width, .y = 50 }, c.ImGuiCond_Always);
        c.ImGui_PushStyleColorImVec4(
            c.ImGuiCol_ModalWindowDimBg,
            .{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 0.3 },
        );
        defer c.ImGui_PopStyleColor();
        if (!c.ImGui_BeginPopupModal(
            "Project Explorer",
            &self.visible,
            c.ImGuiWindowFlags_NoDocking |
                c.ImGuiWindowFlags_NoSavedSettings |
                c.ImGuiWindowFlags_NoResize |
                c.ImGuiWindowFlags_NoTitleBar |
                c.ImGuiWindowFlags_NoCollapse,
        )) {
            return;
        }
    }
    defer self.first_draw = false;
    defer c.ImGui_EndPopup();

    const window_pos = c.ImGui_GetWindowPos();

    {
        const avail = c.ImGui_GetContentRegionAvail();
        if (self.find_str.length() == 0) {
            c.ImGui_PushFont(Editor.roboto14);
        } else {
            c.ImGui_PushFont(Editor.roboto24);
        }
        defer c.ImGui_PopFont();
        c.ImGui_PushStyleColorImVec4(
            c.ImGuiCol_FrameBg,
            std.mem.zeroes(c.ImVec4),
        );
        defer c.ImGui_PopStyleColor();
        if (self.first_draw) c.ImGui_SetKeyboardFocusHere();
        _ = c.ImGui_InputTextWithHintAndSizeEx(
            "##find-query",
            "e.g. \"material,mesh: barrel\" finds all materials and meshes with barrel in their path",
            self.find_str.buf,
            @intCast(self.find_str.size()),
            avail,
            c.ImGuiInputTextFlags_CallbackResize | c.ImGuiInputTextFlags_EnterReturnsTrue | c.ImGuiInputTextFlags_AutoSelectAll,
            &imutils.ImString.InputTextCallback,
            &self.find_str,
        );
    }

    if (self.find_str.length() == 0) {
        return;
    }

    c.ImGui_SetNextWindowPos(.{ .x = window_pos.x, .y = window_pos.y + 80 }, c.ImGuiCond_Always);
    c.ImGui_SetNextWindowSize(.{ .x = input_width, .y = app_window_extent.y * 0.4 }, c.ImGuiCond_Always);
    if (c.ImGui_Begin("Project Explorer Gallery Window", null, c.ImGuiWindowFlags_NoTitleBar | c.ImGuiWindowFlags_NoFocusOnAppearing | c.ImGuiWindowFlags_NoResize)) {
        defer c.ImGui_End();
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
    (struct {
        fn f(this: *Self) !void {
            const root = try Resources.findResourceNode("/") orelse return error.NoResourceIndexed;
            try this.indexResourceNode(root);
        }
    }).f(self) catch |err| log.err("{}, Failed to index resources", .{err});
}

fn indexResourceNode(self: *Self, node: *const Resources.ResourceNode) !void {
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
    const preview = Event(.{ *c.ImDrawList, *const Entry }).callback(void, &void_, struct {
        fn f(_: *void, drawlist: *c.ImDrawList, entry: *const Entry) void {
            const ty = entry.kind.resource.type;
            const icon = Editor.getImGuiTexture(ty.fileIconUri()) catch return;
            c.ImDrawList_AddImage(drawlist, icon, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 });
        }
    }.f);

    try self.index.put(resource.uri.spanZ(), .{ .kind = .{ .resource = resource }, .preview = preview });
}

const Kind = union(enum) {
    resource: Resources.Resource,
};

const Entry = struct {
    kind: Kind,
    preview: Event(.{ *c.ImDrawList, *const Entry }).Callback,
};
