const std = @import("std");
const log = std.log.scoped(.EditorDatabase);

const Uuid = @import("yume").Uuid;
const collections = @import("yume").collections;

const Self = @This();

const ProjectDatabase = struct {
    last_open_project: ?[:0]u8 = null,
    last_open_scene: ?Uuid = null,
};

const LogsDatabase = struct {
    const LogFilters = struct {
        err: bool = true,
        warn: bool = true,
        info: bool = true,
        debug: bool = true,
    };

    filters: LogFilters = .{},
    scopes: collections.StringSentinelArrayHashMap(0, void),

    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        try jws.beginObject();

        try jws.objectField("filters");
        try jws.write(self.filters);

        try jws.objectField("scopes");
        try jws.write(self.scopes.keys());

        try jws.endObject();
    }

    pub fn jsonParse(a: std.mem.Allocator, jrs: anytype, opts: std.json.ParseOptions) !@This() {
        if (try jrs.next() != .object_begin) return error.UnexpectedEndOfInput;

        var result: @This() = .{
            .scopes = collections.StringSentinelArrayHashMap(0, void).init(a),
        };

        while (true) {
            const field_name = switch (try jrs.nextAlloc(a, .alloc_if_needed)) {
                inline .string, .allocated_string => |slice| slice,
                .object_end => break,
                else => |tk| {
                    log.err("{}\n", .{tk});
                    return error.UnexpectedToken;
                },
            };

            if (std.mem.eql(u8, field_name, "filters")) {
                result.filters = try std.json.innerParse(@TypeOf(result.filters), a, jrs, opts);
            } else if (std.mem.eql(u8, field_name, "scopes")) {
                var inner_opts = opts;
                inner_opts.allocate = .alloc_always;
                const array = try std.json.innerParse([][:0]u8, a, jrs, inner_opts);

                for (array) |it| {
                    try result.scopes.put(it, {});
                }
            } else {
                try jrs.skipValue();
            }
        }

        return result;
    }
};

const EditorDatabase = struct {
    project: ProjectDatabase = .{},
    logs: LogsDatabase,
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
    if (storage().project.last_open_project) |lop| {
        if (value != null and value.?.ptr == lop.ptr) {
            return;
        }
        instance.db_arena.allocator().free(lop);
    }

    if (value != null) {
        storage().project.last_open_project = try instance.db_arena.allocator().dupeZ(u8, value.?);
    } else {
        storage().project.last_open_project = null;
    }
}

fn load() !void {
    const end_pos = try instance.file.getEndPos();
    var new_arena: *std.heap.ArenaAllocator = undefined;
    if (end_pos > 0) {
        const buf = try instance.file.readToEndAlloc(instance.allocator, 20_000);
        defer instance.allocator.free(buf);
        const parsed = try std.json.parseFromSlice(EditorDatabase, instance.allocator, buf, .{});
        instance.db = parsed.value;
        new_arena = parsed.arena;
    } else {
        instance.db = EditorDatabase{
            .logs = .{
                .scopes = collections.StringSentinelArrayHashMap(0, void).init(instance.allocator),
            },
        };
        new_arena = try instance.allocator.create(std.heap.ArenaAllocator);
        new_arena.* = std.heap.ArenaAllocator.init(instance.allocator);
    }

    if (instance.loaded) {
        (std.json.Parsed(void){ .arena = instance.db_arena, .value = {} }).deinit();
    }
    instance.db_arena = new_arena;
    instance.loaded = true;
}
