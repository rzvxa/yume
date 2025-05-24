const std = @import("std");
const log = std.log.scoped(.scene);

const ecs = @import("ecs.zig");
const Dynamic = @import("serialization/dynamic.zig").Dynamic;
const GameApp = @import("GameApp.zig");
const assets = @import("assets.zig");
const Uuid = @import("uuid.zig").Uuid;
const Vec3 = @import("math3d.zig").Vec3;
const Mat4 = @import("math3d.zig").Mat4;
const Quat = @import("math3d.zig").Quat;
const utils = @import("utils.zig");

pub const Scene = struct {
    const Self = @This();

    handle: ?assets.SceneHandle,
    root: *Object,
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);

        var arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        const a = arena.allocator();

        self.* = .{
            .handle = null,
            .arena = arena,
            .allocator = a,
            .root = undefined,
        };
        self.root = Object.initRoot(self.allocator) catch @panic("OOM");

        return self;
    }

    pub fn deinit(self: *Self) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
        allocator.destroy(self);
    }

    pub fn dfs(self: *Scene) std.mem.Allocator.Error!Dfs {
        return try Dfs.init(self.allocator, self.root);
    }

    pub fn fromEcs(allocator: std.mem.Allocator, world: ecs.World, root: ecs.Entity, ctx: *GameApp) !*Self {
        var self = try Self.init(allocator);

        self.root.deinit();
        self.root = try Object.fromEcs(self.allocator, world, root, null, ctx);
        const root_name = try self.allocator.realloc(self.root.name, 4);
        self.root.name = @ptrCast(root_name);
        @memset(self.root.name, 0);
        @memcpy(self.root.name[0..4], "root");
        return self;
    }

    pub fn fromJson(
        allocator: std.mem.Allocator,
        json: []const u8,
        o: std.json.ParseOptions,
    ) !*Self {
        var scanner = std.json.Scanner.initCompleteInput(allocator, json);
        defer scanner.deinit();

        var jrs = &scanner;

        var tk = try jrs.next();
        if (tk != .object_begin) return error.UnexpectedEndOfInput;

        var result = try allocator.create(Self);
        errdefer allocator.destroy(result);

        var arena = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();

        result.* = Self{
            .handle = null,
            .arena = arena,
            .allocator = a,
            .root = undefined,
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

            if (std.mem.eql(u8, field_name, "root")) {
                var ptrmap = std.AutoHashMap(Uuid, *anyopaque).init(a);
                defer ptrmap.deinit();
                result.root = try Object.jsonParseGraph(a, jrs, o, .{ .ptrmap = &ptrmap });
            } else {
                try jrs.skipValue();
            }
        }

        return result;
    }

    pub fn jsonStringify(self: Self, jws: anytype) !void {
        try jws.beginObject();

        try jws.objectField("root");
        try self.root.jsonStringifyGraph(jws);
        try jws.endObject();
    }
};

pub const Dfs = struct {
    const Self = @This();

    stack: std.ArrayList(*Object),

    pub fn init(allocator: std.mem.Allocator, root: *Object) !Self {
        var self = Self{
            .stack = try std.ArrayList(*Object).initCapacity(allocator, 1),
        };
        self.stack.appendAssumeCapacity(root);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
    }

    pub fn next(self: *Self) !?*Object {
        if (self.stack.items.len == 0) return null;

        const obj = self.stack.pop();
        for (obj.children.items) |o| {
            try self.stack.append(o);
        }
        return obj;
    }
};

const Object = struct {
    const Self = @This();

    uuid: Uuid,
    name: [:0]u8,
    ident: ?[:0]u8,
    parent: ?*Object = null,
    children: std.ArrayList(*Object),
    components: std.StringArrayHashMap(Component),

    fn initRoot(allocator: std.mem.Allocator) !*Object {
        const self = try allocator.create(Self);
        self.* = .{
            .uuid = Uuid.new(),
            .name = try allocator.dupeZ(u8, "root"),
            .ident = try allocator.dupeZ(u8, "root"),
            .children = std.ArrayList(*Object).init(allocator),
            .components = std.StringArrayHashMap(Component).init(allocator),
        };
        return self;
    }

    fn deinit(self: *Self) void {
        const allocator = self.children.allocator;
        allocator.free(self.name);
        self.children.deinit();
        self.components.deinit();
        allocator.destroy(self);
    }

    pub fn findChildren(self: *Self, obj: *Object) ?usize {
        for (self.children.items, 0..) |c, i| {
            if (c == obj) {
                return i;
            }
        }
        return null;
    }

    pub fn jsonStringify(self: Self, jws: anytype) !void {
        return jws.write(self.uuid.urn());
    }

    pub fn jsonStringifyGraph(self: Self, jws: anytype) !void {
        try jws.beginObject();

        try jws.objectField("uuid");
        try jws.write(self.uuid.urn());

        try jws.objectField("name");
        try jws.write(self.name);

        try jws.objectField("ident");
        try jws.write(self.ident);

        try jws.objectField("parent");
        try jws.write(self.parent);

        try jws.objectField("components");
        try jws.beginObject();
        {
            var iter = self.components.iterator();
            while (iter.next()) |entry| {
                try jws.objectField(entry.key_ptr.*);
                try jws.write(entry.value_ptr.*);
            }
        }
        try jws.endObject();
        // try jws.write(self.components.key);

        try jws.objectField("children");
        try jws.beginArray();
        for (self.children.items) |child| {
            try child.jsonStringifyGraph(jws);
        }
        try jws.endArray();

        try jws.endObject();
    }

    pub fn jsonParseGraph(
        a: std.mem.Allocator,
        jrs: anytype,
        o: anytype,
        ctx: struct {
            ptrmap: *std.AutoHashMap(Uuid, *anyopaque),
        },
    ) !*Self {
        var tk = try jrs.next();
        if (tk != .object_begin) return error.UnexpectedEndOfInput;

        const result = try a.create(Object);
        result.* = .{
            .uuid = .{ .raw = 0 },
            .name = try a.allocSentinel(u8, 0, 0),
            .ident = null,
            .children = std.ArrayList(*Object).init(a),
            .components = std.StringArrayHashMap(Component).init(a),
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

            if (std.mem.eql(u8, field_name, "uuid")) {
                result.uuid = try Uuid.jsonParse(a, jrs, o);
                try ctx.ptrmap.put(result.uuid, result);
            } else if (std.mem.eql(u8, field_name, "name")) {
                result.name = switch (try jrs.next()) {
                    inline .string => |slice| try a.dupeZ(u8, slice),
                    else => {
                        log.err("{}\n", .{tk});
                        return error.UnexpectedToken;
                    },
                };
            } else if (std.mem.eql(u8, field_name, "ident")) {
                result.ident = switch (try jrs.next()) {
                    inline .string => |slice| try a.dupeZ(u8, slice),
                    inline .null => null,
                    else => {
                        log.err("{}\n", .{tk});
                        return error.UnexpectedToken;
                    },
                };
            } else if (std.mem.eql(u8, field_name, "parent")) {
                if (try jrs.peekNextTokenType() == .null) {
                    _ = try jrs.next();
                    result.parent = null;
                    continue;
                }
                const parent_id = try Uuid.jsonParse(a, jrs, o);
                const ptr = ctx.ptrmap.get(parent_id);
                if (ptr) |p| {
                    result.parent = @as(*Self, @ptrCast(@alignCast(p)));
                    continue;
                }
                log.err("Failed to resolve reference {s}", .{parent_id.urn()});
                return error.UnexpectedToken;
            } else if (std.mem.eql(u8, field_name, "components")) {
                const dyn = try Dynamic.jsonParse(a, jrs, o);
                const obj = dyn.expect(.object) catch return error.UnexpectedToken;
                for (obj.fields()) |field| {
                    try result.components.put(std.mem.span(field.key), field.value);
                }
            } else if (std.mem.eql(u8, field_name, "children")) {
                std.debug.assert(try jrs.next() == .array_begin);
                if (result.uuid.raw == 0) {
                    return error.SyntaxError;
                }
                while (true) {
                    const peek = try jrs.peekNextTokenType();
                    if (peek == .array_end) {
                        _ = try jrs.next();
                        break;
                    }
                    const children = try Self.jsonParseGraph(a, jrs, o, ctx);
                    try result.children.append(children);
                }
            } else {
                try jrs.skipValue();
            }
        }

        return result;
    }

    pub fn fromEcs(allocator: std.mem.Allocator, world: ecs.World, entity: ecs.Entity, parent: ?*Self, ctx: *GameApp) !*Self {
        const name = world.getMetaName(entity);
        const ident = if (world.getPathName(entity)) |ident| try allocator.dupeZ(u8, ident) else null;
        const uuid = blk: {
            if (world.getUuid(entity)) |uuid| {
                break :blk uuid;
            } else {
                const uuid = Uuid.new();
                log.warn(
                    "Attempting to serialize an entity without a UUID," ++
                        " assigning a new UUID {s} to the entity {d} to it.\n",
                    .{ uuid.urn(), entity },
                );
                world.set(entity, ecs.components.Uuid, .{ .value = uuid });
                break :blk uuid;
            }
        };
        var self = try allocator.create(Self);
        self.* = .{
            .uuid = uuid,
            .name = try allocator.dupeZ(u8, name),
            .ident = ident,
            .parent = parent,
            .children = std.ArrayList(*Object).init(allocator),
            .components = std.StringArrayHashMap(Component).init(allocator),
        };

        for (try world.getType(entity)) |id| {
            if (ecs.isPair(id)) {
                continue;
            }
            const comp_id = id & ecs.masks.component;
            const comp_path = try world.getPathAlloc(comp_id, allocator);
            const def = ctx.components.get(comp_path) orelse return error.ComponentDefinitionNotFound;
            const ser = def.serialize orelse continue;
            const ptr = world.getId(entity, id).?;
            const res = ser(ptr, &allocator);
            if (!res.ok) {
                return error.FailedToSerializeComponent;
            }

            try self.components.put(comp_path, res.result);
        }

        const children = try world.childrenSorted(entity, allocator);
        defer allocator.free(children);
        for (children) |child| {
            const serialized = try Self.fromEcs(allocator, world, child, self, ctx);
            try self.children.append(serialized);
        }
        return self;
    }
};

pub const Component = Dynamic;
