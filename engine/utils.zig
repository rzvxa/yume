const c = @import("clibs");

const std = @import("std");

const log = std.log.scoped(.vulkan_engine);

// Error checking for vulkan and SDL

pub fn checkSdl(res: c_int) void {
    if (res != 0) {
        log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}

pub fn checkSdlBool(res: c.SDL_bool) void {
    if (res != c.SDL_TRUE) {
        log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}

pub const TypeId = usize;

pub fn typeId(comptime T: type) TypeId {
    const H = struct {
        const _ = T;
        var byte: u8 = 0;
    };
    return @intFromPtr(&H.byte);
}
