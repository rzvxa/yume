const c = @import("clibs");

const builtin = @import("builtin");
const std = @import("std");

const utils = @import("yume").utils;

const Project = @import("../Project.zig");

const imutils = @import("../imutils.zig");
const Editor = @import("../Editor.zig");

const Self = @This();

const THIRD_PARTY_LICENSES = @embedFile("THIRD-PARTY-LICENSE");

var version_buf: [128]u8 = undefined;
var version_text: [:0]const u8 = undefined;
var formatVersionText = std.once(struct {
    fn f() void {
        const v = @import("yume").version;
        version_text = std.fmt.bufPrintZ(
            &version_buf,
            "Version {d}.{d}.{d}",
            .{ v.major, v.minor, v.patch },
        ) catch @panic("Failed to format version text");
    }
}.f);

id: c.ImGuiID = undefined,
is_open: bool = false,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !Self {
    formatVersionText.call();
    return Self{ .allocator = allocator };
}

pub fn deinit(_: *Self) void {}

pub fn open(self: *Self) void {
    self.is_open = true;
}

pub fn close(self: *Self) void {
    self.is_open = false;
}

pub fn draw(self: *Self) !void {
    if (!self.is_open) return;
    c.ImGui_PushID("about-modal");
    defer c.ImGui_PopID();

    const viewport = c.ImGui_GetMainViewport();
    c.ImGui_SetNextWindowPos(.{
        .x = @max(1, (viewport.*.Size.x - 700) / 2),
        .y = @max(1, (viewport.*.Size.y - 450) / 2),
    }, c.ImGuiCond_Appearing);
    c.ImGui_SetNextWindowSize(.{ .x = 700, .y = 450 }, c.ImGuiCond_Appearing);

    const title = "About";
    const flags = c.ImGuiWindowFlags_NoDocking | c.ImGuiWindowFlags_NoCollapse | c.ImGuiWindowFlags_NoSavedSettings;
    self.id = c.ImGui_GetID(title);
    _ = c.ImGui_Begin(title, &self.is_open, flags);
    defer c.ImGui_End();
    if (self.is_open) {
        const window_size = c.ImGui_GetWindowSize();

        imutils.alignHorizontal(window_size.x, 0.5);
        c.ImGui_BeginGroup();
        defer c.ImGui_EndGroup();

        c.ImGui_NewLine();
        imutils.alignHorizontal(123, 0.5);
        c.ImGui_Image(Editor.yume_logo_ds, c.ImVec2{ .x = 123, .y = 163 });
        c.ImGui_PushFont(Editor.ubuntu32);
        defer c.ImGui_PopFont();
        c.ImGui_NewLine();
        imutils.textAlignedHorizontal("Yume", 0.5);

        c.ImGui_PushFont(Editor.ubuntu14);
        defer c.ImGui_PopFont();
        imutils.textAlignedHorizontal(version_text, 0.5);

        if (imutils.textLinkAlignedHorizontal("GitHub", 0.5)) {
            try utils.tryOpenWithOsDefaultApplication(self.allocator, "https://github.com/rzvxa/yume");
        }
        if (imutils.textLinkAlignedHorizontal("Yume itself is licensed under MIT", 0.5)) {
            try utils.tryOpenWithOsDefaultApplication(self.allocator, "https://github.com/rzvxa/yume/blob/main/LICENSE");
        }

        imutils.textAlignedHorizontal("Third-Party licenses(let us know if anything is missing here)", 0.5);

        _ = c.ImGui_InputTextMultilineEx(
            "##third-party-licenses",
            @constCast(THIRD_PARTY_LICENSES.ptr),
            THIRD_PARTY_LICENSES.len + 1,
            .{ .x = window_size.x, .y = c.ImGui_GetContentRegionAvail().y },
            c.ImGuiInputTextFlags_ReadOnly,
            null,
            null,
        );
    }
}
