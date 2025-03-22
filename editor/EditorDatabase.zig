const std = @import("std");

const Uuid = @import("yume").Uuid;

const Self = @This();

const EditorDatabase = struct {
    last_open_project: ?[]u8 = null,
    last_open_scene: ?Uuid = null,
};

var instance: Self = undefined;

allocator: std.mem.Allocator = undefined,
loaded: bool = false,
file: std.fs.File = undefined,
db: EditorDatabase = undefined,
db_arena: *std.heap.ArenaAllocator = undefined,

pub fn init(a: std.mem.Allocator, filepath: []const u8) !void {
    try std.fs.cwd().makePath(std.fs.path.dirname(filepath).?);
    instance = .{
        .allocator = a,
        .file = try std.fs.cwd().createFile(filepath, .{ .read = true, .lock = .exclusive, .truncate = false }),
    };
    try load();
}

pub fn deinit() void {
    std.debug.assert(instance.loaded);
    (std.json.Parsed(void){ .arena = instance.db_arena, .value = {} }).deinit();
    instance.file.close();
}

pub fn storage() *EditorDatabase {
    std.debug.assert(instance.loaded);
    return &instance.db;
}

pub fn flush() !void {
    std.debug.assert(instance.loaded);
    const json = try std.json.stringifyAlloc(instance.allocator, instance.db, .{ .whitespace = .indent_4 });
    defer instance.allocator.free(json);
    try instance.file.setEndPos(0);
    try instance.file.seekTo(0);
    try instance.file.writeAll(json);
}

pub fn setLastOpenProject(value: ?[]const u8) !void {
    if (storage().last_open_project) |lop| {
        if (value != null and value.?.ptr == lop.ptr) {
            return;
        }
        instance.db_arena.allocator().free(lop);
    }

    if (value != null) {
        storage().last_open_project = try instance.db_arena.allocator().dupe(u8, value.?);
    } else {
        storage().last_open_project = null;
    }
}

fn load() !void {
    const end_pos = try instance.file.getEndPos();
    var new_arena: *std.heap.ArenaAllocator = undefined;
    std.debug.print("HERE {d}\n", .{end_pos});
    if (end_pos > 0) {
        const buf = try instance.file.readToEndAlloc(instance.allocator, 20_000);
        defer instance.allocator.free(buf);
        const parsed = try std.json.parseFromSlice(EditorDatabase, instance.allocator, buf, .{});
        instance.db = parsed.value;
        new_arena = parsed.arena;
    } else {
        instance.db = EditorDatabase{};
        new_arena = try instance.allocator.create(std.heap.ArenaAllocator);
        new_arena.* = std.heap.ArenaAllocator.init(instance.allocator);
    }

    if (instance.loaded) {
        (std.json.Parsed(void){ .arena = instance.db_arena, .value = {} }).deinit();
    }
    instance.db_arena = new_arena;
    instance.loaded = true;
}
