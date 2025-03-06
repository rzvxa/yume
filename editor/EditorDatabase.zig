const std = @import("std");

const KvStorage = @import("yume").KvStorage;

const EditorDatabase = struct {

};

var allocator: std.mem.Allocator = undefined;
var loaded: bool = false;
var file: std.fs.File = undefined;
var parsed: std.json.Parsed(Storage) = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    storage = KvStorage.init(allocator, "~/.yumed/db") catch @panic("OOM");
}

pub fn deinit() void {
    storage.deinit();
}

pub fn init(allocator: std.mem.Allocator, filepath: []const u8) !Self {
    var self = .{
        .allocator = allocator,
        .file = try std.fs.cwd().openFile(filepath, .{}),
    };
    self.load();
}

pub fn deinit(self: *Self) void {
    std.debug.assert(self.loaded);
    self.parsed.deinit();
    self.file.close();
}

pub fn storage(self: *Self) *Storage {
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
    self.parsed = try std.json.parseFromSlice(Storage, self.allocator, buf, .{});
}
