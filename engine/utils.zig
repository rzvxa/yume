const c = @import("clibs");

const builtin = @import("builtin");
const std = @import("std");

const log = std.log.scoped(.vulkan_engine);

// Error checking for vulkan and SDL

pub fn checkSdl(res: bool) void {
    if (res != true) {
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

// caller owns the data
pub fn getHomeDirectoryOwned(allocator: std.mem.Allocator) ![]u8 {
    if (comptime builtin.os.tag == .windows) {
        return std.process.getEnvVarOwned(allocator, "USERPROFILE");
    } else {
        return std.process.getEnvVarOwned(allocator, "HOME");
    }
}

pub fn pathExists(path: []const u8) !bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch |e| switch (e) {
        error.FileNotFound => {
            return false;
        },
        else => return e,
    };
    defer dir.close();
    std.debug.print("HERE fullpath {s} {}\n", .{ path, try dir.createFile("Hello.txt", .{}) });
    return true;
}

fn AbsorbSentinelReturnType(comptime Slice: type) type {
    const info = @typeInfo(Slice).Pointer;
    std.debug.assert(info.size == .Slice);
    return @Type(.{
        .Pointer = .{
            .size = info.size,
            .is_const = info.is_const,
            .is_volatile = info.is_volatile,
            .is_allowzero = info.is_allowzero,
            .alignment = info.alignment,
            .address_space = info.address_space,
            .child = info.child,
            .sentinel = null,
        },
    });
}

/// If the provided slice is not sentinel terminated, do nothing and return that slice.
/// If it is sentinel-terminated, return a non-sentinel-terminated slice with the
/// length increased by one to include the absorbed sentinel element.
pub fn absorbSentinel(slice: anytype) AbsorbSentinelReturnType(@TypeOf(slice)) {
    const info = @typeInfo(@TypeOf(slice)).Pointer;
    std.debug.assert(info.size == .Slice);
    if (info.sentinel == null) {
        return slice;
    } else {
        return slice.ptr[0 .. slice.len + 1];
    }
}
