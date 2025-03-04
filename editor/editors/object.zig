const c = @import("clibs");

const std = @import("std");

const Object = @import("yume").Object;

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

pub fn deinit(_: *Self) void {}

pub fn edit(self: *Self, _: *Object) void {
    // self.allocator.realloc()
    const Callback = struct {
        buf: *std.ArrayList(u8),
        fn InputTextCallback(data: [*c]c.ImGuiInputTextCallbackData) callconv(.C) c_int {
            const user_data = @as(*@This(), @ptrCast(@alignCast(data.*.UserData)));
            if (data.*.EventFlag == c.ImGuiInputTextFlags_CallbackResize) {
                // Resize string callback
                // If for some reason we refuse the new length (BufTextLen) and/or capacity (BufSize) we need to set them back to what we want.
                // std::string* str = user_data->Str;
                std.debug.assert(data.*.Buf == user_data.buf.items.ptr);
                user_data.buf.resize(@intCast(data.*.BufTextLen)) catch @panic("OOM");
                data.*.Buf = user_data.buf.items.ptr;
            }
            return 0;
        }
    };
    var callback = Callback{ .buf = &self.name };
    _ = c.ImGui_InputTextEx("Name", self.name.items.ptr, self.name.capacity, c.ImGuiInputTextFlags_CallbackResize, Callback.InputTextCallback, &callback);
}
