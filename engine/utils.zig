const c = @import("clibs");

const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.utils);

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
    var dir = std.fs.cwd().openDir(path, .{}) catch |e| switch (e) {
        error.NotDir => {
            var file = std.fs.cwd().openFile(path, .{}) catch |e2| switch (e2) {
                error.FileNotFound => {
                    return false;
                },
                else => return e2,
            };
            defer file.close();
            return true;
        },
        error.FileNotFound => {
            return false;
        },
        else => return e,
    };
    defer dir.close();
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

pub fn levenshtein(a: []const u8, b: []const u8, allocator: std.mem.Allocator) usize {
    const rows = a.len + 1;
    const cols = b.len + 1;

    const alloc = blk: {
        var s = std.heap.stackFallback(4096, allocator);
        break :blk s.get();
    };
    var matrix = alloc.alloc(usize, rows * cols) catch unreachable;

    for (0..rows) |i| {
        matrix[i * cols] = i;
    }
    for (0..cols) |j| {
        matrix[j] = j;
    }

    for (1..rows) |i| {
        for (1..cols) |j| {
            const cost: usize = if (a[i - 1] == b[j - 1]) 0 else 1;
            matrix[i * cols + j] = @min(matrix[(i - 1) * cols + j] + 1, @min(
                matrix[i * cols + j - 1] + 1,
                matrix[(i - 1) * cols + j - 1] + cost,
            ));
        }
    }

    const result = matrix[rows * cols - 1];

    alloc.free(matrix);

    return result;
}

pub fn tryOpenWithOsDefaultApplication(allocator: std.mem.Allocator, path: []const u8) !void {
    _ = switch (builtin.os.tag) {
        .windows => std.process.Child.run(.{ .allocator = allocator, .argv = &.{
            "cmd",
            "/c",
            "start",
            "\"\"",
            path,
        } }) catch return error.FailedToOpen,
        .linux => std.process.Child.run(.{ .allocator = allocator, .argv = .{ "xdg-open", path } }) catch return error.LauncherNotFound,
        .macos => std.process.Child.run(.{ .allocator = allocator, .argv = .{ "open", path } }) catch return error.LauncherNotFound,
        else => |p| @compileError("Unsupported platform: " ++ p),
    };
}

pub const BaseExtensionSplitResult = struct {
    base: []const u8,
    ext: []const u8,
    index_of_dot: ?usize, // if null, path has no extension part
};

// splits the path into extension and everything but the extension
// both slices are always guaranteed to be in valid range of the path
// similar to the standard library's extension method,
// the extension includes the preceding dot.
// Example: 'a/b/c/d.zig' => { base: 'a/b/c/d', ext: '.zig' }
// Example: 'a/b/c/d.zig.zag' => { base: 'a/b/c/d.zig', ext: '.zag' }
pub fn baseExtensionSplit(path: []const u8) BaseExtensionSplitResult {
    const index = std.mem.lastIndexOfScalar(u8, path, '.') orelse return .{
        .base = path,
        .ext = path[path.len..],
        .index_of_dot = null,
    };
    return if (index == 0) .{ // dot file (e.g. `.bashrc`)
        .base = path[0..],
        .ext = path[path.len..],
        .index_of_dot = null,
    } else .{
        .ext = path[index..],
        .base = path[0..index],
        .index_of_dot = index,
    };
}

// mutates the path in-place and returns it
// this function replaces `\\` with `/` in-place and therefore path is guaranteed
// to always have enough room for the result.
pub fn normalizePathSep(path: []u8) []u8 {
    if (builtin.os.tag == .windows) {
        for (path, 0..) |char, i| {
            if (char == '\\') {
                path[i] = '/';
            }
        }
    }
    return path;
}

pub fn normalizePathSepZ(path: [*:0]u8) [*:0]u8 {
    if (builtin.os.tag == .windows) {
        var i: usize = 0;
        while (true) : (i += 1) {
            if (path[i] == 0) {
                break;
            }

            if (path[i] == '\\') {
                path[i] = '/';
            }
        }
    }
    return path;
}
