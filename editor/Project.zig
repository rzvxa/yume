const std = @import("std");
const log = std.log.scoped(.Project);

const Uuid = @import("yume").Uuid;

const AssetLoader = @import("yume").assets.AssetLoader;
const EditorDatabase = @import("EditorDatabase.zig");
const Resources = @import("Resources.zig");
const Watch = @import("Watch.zig");

const Self = @This();

var instance: ?Self = null;

allocator: std.mem.Allocator,

yume_version: std.SemanticVersion = @import("yume").version,
project_name: []const u8,
scenes: std.ArrayList(Uuid),
default_scene: Uuid,

// unserialized data
watcher: ?*Watch = null,

pub fn load(allocator: std.mem.Allocator, path: []const u8) !void {
    if (instance) |*ins| {
        ins.unload();
    }
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const s = try file.readToEndAlloc(allocator, 30_000_000);
    defer allocator.free(s);
    instance = (try std.json.parseFromSliceLeaky(Self, allocator, s, .{}));

    var project_root = try std.fs.openDirAbsolute(std.fs.path.dirname(path) orelse return error.InvalidPath, .{});
    defer project_root.close();
    try project_root.setAsCwd();

    if (Watch.supported_platform) {
        instance.?.watcher = try Watch.init(allocator, ".");
    }

    try Resources.reinit(allocator);
    try Resources.indexCwd();

    try EditorDatabase.setLastOpenProject(path);
}

pub fn unload(self: *Self) void {
    if (self.watcher) |w| w.deinit();
    self.scenes.deinit();
    self.allocator.free(self.project_name);
}

pub fn update() void {
    if (instance.?.watcher) |w| {
        var ctx = {};
        w.dispatch(void, &struct {
            fn f(_: *void, e: Watch.Event) void {
                switch (e) {
                    .add, .remove, .modify => |s| log.debug("tag: {s} {s}", .{ @tagName(e), s }),
                    .rename => |rn| log.debug("tag: {s} old: {s}, new: {s}", .{ @tagName(e), rn.old, rn.new }),
                }
            }
        }.f, &ctx) catch |e| log.err("Watch error: {}", .{e});
    }
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
