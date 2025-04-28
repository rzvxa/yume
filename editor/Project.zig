const std = @import("std");
const log = std.log.scoped(.Project);

const Uuid = @import("yume").Uuid;

const AssetLoader = @import("yume").assets.AssetLoader;
const EditorDatabase = @import("EditorDatabase.zig");
const AssetsDatabase = @import("AssetsDatabase.zig");

const Self = @This();

var instance: ?Self = null;

allocator: std.mem.Allocator,

yume_version: std.SemanticVersion = @import("yume").version,
project_name: []const u8,
scenes: std.ArrayList(Uuid),
default_scene: Uuid,

resources: std.AutoHashMap(Uuid, AssetsDatabase.Resource),

// unserialized data
resources_index: std.StringHashMap(Uuid),
resources_builtins: std.AutoHashMap(Uuid, AssetsDatabase.Resource),

pub fn load(allocator: std.mem.Allocator, path: []const u8) !void {
    if (instance) |*ins| {
        ins.unload();
    }
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const s = try file.readToEndAlloc(allocator, 30_000_000);
    defer allocator.free(s);
    instance = (try std.json.parseFromSliceLeaky(Self, allocator, s, .{}));
    instance.?.resources_index = std.StringHashMap(Uuid).init(allocator);
    instance.?.resources_builtins = std.AutoHashMap(Uuid, AssetsDatabase.Resource).init(allocator);

    var project_root = try std.fs.openDirAbsolute(std.fs.path.dirname(path) orelse return error.InvalidPath, .{});
    defer project_root.close();
    try project_root.setAsCwd();

    var iter = instance.?.resources.iterator();
    while (iter.next()) |it| {
        try AssetsDatabase.register(.{ .urn = &it.key_ptr.urn(), .path = it.value_ptr.path });
    }

    try EditorDatabase.setLastOpenProject(path);
}

pub fn unload(self: *Self) void {
    self.scenes.deinit();
    {
        var it = self.resources_index.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.key_ptr.*);
        }
    }
    self.resources_index.deinit();
    {
        var it = self.resources.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.value_ptr.path);
        }
    }
    self.resources.deinit();
    {
        var it = self.resources_builtins.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.value_ptr.path);
        }
    }
    self.resources_builtins.deinit();
    self.allocator.free(self.project_name);
}

pub fn current() ?*Self {
    if (instance) |*it| {
        return it;
    }
    return null;
}

pub fn jsonStringify(self: Self, jws: anytype) !void {
    try jws.beginObject();

    try jws.objectField("yume_version");
    { // HACK: for some reason std.fmt doesn't play nice with std.json writer
        const v = self.yume_version;
        try jws.print("\"{d}.{d}.{d}", .{ v.major, v.minor, v.patch });
        if (v.pre) |pre| try jws.print("-{s}", .{pre});
        if (v.build) |build| try jws.print("+{s}", .{build});
        try jws.stream.writeAll("\"");
    }

    try jws.objectField("name");
    try jws.write(self.project_name);

    try jws.objectField("scenes");
    try jws.write(self.scenes.items);

    try jws.objectField("default_scene");
    try jws.write(self.default_scene);

    try jws.objectField("resources");
    {
        try jws.beginArray();
        var it = self.resources.iterator();
        while (it.next()) |kv| {
            try jws.write(kv.value_ptr.*);
        }
        try jws.endArray();
    }
    try jws.endObject();
}

pub fn jsonParse(a: std.mem.Allocator, jrs: anytype, o: anytype) !Self {
    var tk = try jrs.next();
    if (tk != .object_begin) return error.UnexpectedEndOfInput;

    var result = Self{
        .allocator = a,
        .yume_version = undefined,
        .project_name = "UNNAMED PROJECT",
        .scenes = undefined,
        .default_scene = undefined,
        .resources = undefined,
        .resources_index = undefined,
        .resources_builtins = undefined,
    };

    while (true) {
        tk = try jrs.nextAlloc(a, .alloc_if_needed);
        if (tk == .object_end) break;

        const field_name = switch (tk) {
            inline .string, .allocated_string => |slice| slice,
            else => {
                log.err("{}\n", .{tk});
                return error.UnexpectedToken;
            },
        };

        if (std.mem.eql(u8, field_name, "yume_version")) {
            result.yume_version = try parseYumeVersion(jrs);
        } else if (std.mem.eql(u8, field_name, "name")) {
            tk = try jrs.nextAlloc(a, .alloc_always);
            result.project_name = switch (tk) {
                inline .allocated_string => |slice| slice,
                else => {
                    return error.UnexpectedToken;
                },
            };
        } else if (std.mem.eql(u8, field_name, "scenes")) {
            result.scenes = try parseScenes(a, jrs);
        } else if (std.mem.eql(u8, field_name, "default_scene")) {
            result.default_scene = try Uuid.jsonParse(a, jrs, o);
        } else if (std.mem.eql(u8, field_name, "resources")) {
            result.resources = try parseResources(a, jrs);
        } else {
            try jrs.skipValue();
        }
    }

    return result;
}

fn parseYumeVersion(jrs: *std.json.Scanner) !std.SemanticVersion {
    const tk = try jrs.next();
    if (tk != .string) return error.UnexpectedToken;

    const version_str = switch (tk) {
        inline .string, .allocated_string => |slice| slice,
        else => return error.UnexpectedToken,
    };

    const parsed_version = std.SemanticVersion.parse(version_str) catch return error.SyntaxError;

    return parsed_version;
}

fn parseScenes(a: std.mem.Allocator, jrs: *std.json.Scanner) !std.ArrayList(Uuid) {
    var tk = try jrs.next();
    if (tk != .array_begin) return error.UnexpectedToken;

    var scenes = std.ArrayList(Uuid).init(a);

    while (true) {
        tk = try jrs.nextAlloc(a, .alloc_always);
        if (tk == .array_end) break;

        const uuid = try Uuid.jsonParse(a, jrs, null);
        try scenes.append(uuid);
    }

    return scenes;
}

fn parseResources(a: std.mem.Allocator, jrs: *std.json.Scanner) !std.AutoHashMap(Uuid, AssetsDatabase.Resource) {
    var tk = try jrs.next();
    if (tk != .array_begin) return error.UnexpectedToken;

    var resources = std.AutoHashMap(Uuid, AssetsDatabase.Resource).init(a);

    while (true) {
        tk = try jrs.next();
        if (tk == .array_end) break;

        if (tk != .object_begin) return error.UnexpectedToken;

        var resource = AssetsDatabase.Resource{
            .id = undefined,
            .path = undefined,
        };

        var uuid: ?Uuid = null;

        while (true) {
            tk = try jrs.nextAlloc(a, .alloc_if_needed);
            if (tk == .object_end) break;

            const field_name = switch (tk) {
                inline .string, .allocated_string => |slice| slice,
                else => return error.UnexpectedToken,
            };

            if (std.mem.eql(u8, field_name, "id")) {
                resource.id = try Uuid.jsonParse(a, jrs, null);
                uuid = resource.id;
            } else if (std.mem.eql(u8, field_name, "path")) {
                tk = try jrs.nextAlloc(a, .alloc_always);
                resource.path = switch (tk) {
                    inline .allocated_string => |slice| slice,
                    else => return error.UnexpectedToken,
                };
            } else {
                try jrs.skipValue();
            }
        }

        if (uuid == null) return error.MissingField;
        try resources.put(uuid.?, resource);
    }

    return resources;
}

fn addBuiltin(opts: struct { urn: []const u8, path: []const u8, category: []const u8 = "builtin" }) !void {
    const id = try Uuid.fromUrnSlice(opts.urn);
    const gameRoot = try gameRootDirectory(instance.?.allocator);
    defer instance.?.allocator.free(gameRoot);
    try instance.?.resources_builtins.put(id, AssetsDatabase.Resource{
        .id = id,
        .path = try std.fs.path.join(instance.?.allocator, &[_][]const u8{ gameRoot, "assets", opts.category, opts.path }),
    });
    const uri = try std.fmt.allocPrint(instance.?.allocator, "{s}://{s}", .{ opts.category, opts.path });
    try instance.?.resources_index.put(uri, id);
}

fn addBuiltinShader(urn: []const u8, path: []const u8) !void {
    const id = try Uuid.fromUrnSlice(urn);
    const gameRoot = try gameRootDirectory(instance.?.allocator);
    defer instance.?.allocator.free(gameRoot);
    const pathspv = try std.fmt.allocPrint(instance.?.allocator, "{s}.{s}", .{ path[0 .. path.len - ".glsl".len], "spv" });
    defer instance.?.allocator.free(pathspv);
    try instance.?.resources_builtins.put(id, AssetsDatabase.Resource{
        .id = id,
        .path = try std.fs.path.join(instance.?.allocator, &[_][]const u8{ gameRoot, "shaders", pathspv }),
    });
    const uri = try std.fmt.allocPrint(instance.?.allocator, "builtin://{s}", .{path});
    try instance.?.resources_index.put(uri, id);
}

inline fn gameRootDirectory(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExeDirPath(&buf);
    const dirname = std.fs.path.dirname(exe_path) orelse return error.InvalidPath;
    return allocator.dupe(u8, dirname);
}
