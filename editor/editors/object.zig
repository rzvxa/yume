const c = @import("clibs");

const std = @import("std");

const Object = @import("yume").Object;
const utils = @import("yume").utils;
const imutils = @import("../imutils.zig");

const Self = @This();

allocator: std.mem.Allocator,

name: std.ArrayList(u8),

pub fn init(allocator: std.mem.Allocator, obj: *Object) Self {
    var self = Self{
        .allocator = allocator,
        .name = std.ArrayList(u8).initCapacity(allocator, obj.name.len + 1) catch @panic("OOM"),
    };
    self.name.appendSliceAssumeCapacity(obj.name);
    self.name.appendAssumeCapacity(0);
    return self;
}

pub fn deinit(self: *Self) void {
    self.name.deinit();
}

pub fn edit(self: *Self, obj: *Object, icon: c.VkDescriptorSet) void {
    const avail = c.ImGui_GetContentRegionAvail();
    const old_pad_y = c.ImGui_GetStyle().*.FramePadding.y;
    c.ImGui_GetStyle().*.FramePadding.y = 0;
    _ = c.ImGui_BeginChildFrameEx(c.ImGui_GetID("object type icon"), c.ImVec2{ .x = 48, .y = 48 }, c.ImGuiWindowFlags_NoBackground);
    c.ImGui_Image(@intFromPtr(icon), c.ImVec2{ .x = 48, .y = 48 });
    c.ImGui_EndChildFrame();
    c.ImGui_GetStyle().*.FramePadding.y = old_pad_y;

    c.ImGui_SameLine();

    _ = c.ImGui_BeginChildFrameEx(c.ImGui_GetID("meta"), c.ImVec2{ .x = avail.x - 48, .y = 48 }, c.ImGuiWindowFlags_NoBackground);
    c.ImGui_TextDisabled("Object:");
    c.ImGui_Separator();

    var enabled = true;
    _ = c.ImGui_Checkbox("###enabled", &enabled);
    c.ImGui_SameLine();

    var callback = imutils.ArrayListU8ResizeCallback{ .buf = &self.name };
    const renamed = c.ImGui_InputTextEx(
        "###Name",
        self.name.items.ptr,
        self.name.capacity,
        c.ImGuiInputTextFlags_CallbackResize,
        imutils.ArrayListU8ResizeCallback.InputTextCallback,
        &callback,
    );

    if (renamed) {
        const len = self.name.items.len;

        var new_slice = (obj.scene.allocator.realloc(utils.absorbSentinel(obj.name), len + 1) catch @panic("OOM"));
        @memcpy(new_slice[0..len], self.name.items);
        new_slice[len] = 0;
        obj.name = new_slice.ptr[0..len :0];
    }

    c.ImGui_EndChildFrame();
}
