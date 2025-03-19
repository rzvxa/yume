const std = @import("std");
const Uuid = @import("yume").Uuid;

const Self = @This();

var instance: ?Self = null;

allocator: std.mem.Allocator,

yume_version: std.SemanticVersion = @import("yume").version,
project_name: []const u8,
scenes: std.ArrayList(Uuid),
default_scene: Uuid,

resources: std.AutoHashMap(Uuid, Resource),

pub fn load(allocator: std.mem.Allocator, path: []const u8) !void {
    if (instance) |*ins| {
        ins.unload();
    }
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const s = try file.readToEndAlloc(allocator, 30_000_000);
    defer allocator.free(s);
    instance = (try std.json.parseFromSlice(Self, allocator, s, .{})).value;
}

pub fn unload(self: *Self) void {
    self.scenes.deinit();
    var it = self.resources.iterator();
    while (it.next()) |kv| {
        self.allocator.free(kv.value_ptr.path);
    }
    self.resources.deinit();
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

pub fn jsonParse(a: std.mem.Allocator, jrs: *std.json.Scanner, o: anytype) !Self {
    var tk = try jrs.next();
    if (tk != .object_begin) return error.UnexpectedEndOfInput;

    var result = Self{
        .allocator = undefined,
        .yume_version = undefined,
        .project_name = undefined,
        .scenes = undefined,
        .default_scene = undefined,
        .resources = undefined,
    };

    while (true) {
        tk = try jrs.nextAlloc(a, .alloc_if_needed);
        if (tk == .object_end) break;

        const field_name = switch (tk) {
            inline .string, .allocated_string => |slice| slice,
            else => {
                std.debug.print("{}\n", .{tk});
                return error.UnexpectedToken;
            },
        };
        std.debug.print("{s}\n", .{field_name});

        if (std.mem.eql(u8, field_name, "yume_version")) {
            result.yume_version = try parseYumeVersion(jrs);
        } else if (std.mem.eql(u8, field_name, "name")) {
            tk = try jrs.nextAlloc(a, .alloc_if_needed);
            result.project_name = switch (tk) {
                inline .string, .allocated_string => |slice| slice,
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
    std.debug.print("{}\n", .{tk});
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

fn parseResources(a: std.mem.Allocator, jrs: *std.json.Scanner) !std.AutoHashMap(Uuid, Resource) {
    var tk = try jrs.next();
    if (tk != .array_begin) return error.UnexpectedToken;

    var resources = std.AutoHashMap(Uuid, Resource).init(a);

    while (true) {
        tk = try jrs.next();
        if (tk == .array_end) break;

        if (tk != .object_begin) return error.UnexpectedToken;

        var resource = Resource{
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
                tk = try jrs.next();
                resource.path = switch (tk) {
                    inline .string => |slice| try a.dupe(u8, slice),
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

pub const Resource = struct {
    id: Uuid,
    path: []u8,
};
