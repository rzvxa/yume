const std = @import("std");

const Self = @This();

const EditorDatabase = struct {};

var allocator: std.mem.Allocator = undefined;
var loaded: bool = false;
var file: std.fs.File = undefined;
var parsed: std.json.Parsed(EditorDatabase) = undefined;

pub fn init(a: std.mem.Allocator, filepath: []const u8) !Self {
    var self = .{
        .allocator = a,
        .file = try std.fs.cwd().openFile(filepath, .{}),
    };
    self.load();
}

pub fn deinit(self: *Self) void {
    std.debug.assert(self.loaded);
    self.parsed.deinit();
    self.file.close();
}

pub fn storage(self: *Self) *EditorDatabase {
    std.debug.assert(self.loaded);
    return &self.parsed.value;
}

pub fn flush(self: *Self) !void {
    std.debug.assert(self.loaded);
    std.json.stringifyAlloc(self.allocator, self.parsed.value, .{ .whitespace = .indent_4 });
}

fn load(self: *Self) !void {
    const buf = try self.file.readToEndAlloc(self.allocator, 20_000);
    defer self.allocator.free(buf);

    if (self.loaded) {
        self.parsed.deinit();
    }
    self.parsed = try std.json.parseFromSlice(EditorDatabase, self.allocator, buf, .{});
}
