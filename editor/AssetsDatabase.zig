const std = @import("std");

const Uuid = @import("yume").Uuid;
const utils = @import("yume").utils;

const Editor = @import("Editor.zig");

const log = std.log.scoped(.AssetsDatabase);

pub const yume_meta_extension_name = ".ym";

pub const Resource = struct {
    pub const Type = enum {
        unknown,
        // yume.json project file used to load the project,
        // if a project structure contains multiple yume.json files - for example in the subdirectories -
        // only the file used to load the project is marked with this tag and all others are
        // registered as normal json files.
        project,
        scene,
        shader,
        mat,
        obj,
        fbx,

        pub fn fromExt(ext: []const u8) Type {
            const eql = std.mem.eql;
            return if (eql(u8, ext, ".scene"))
                .scene
            else if (eql(u8, ext, ".mat"))
                .mat
            else if (eql(u8, ext, ".obj"))
                .obj
            else if (eql(u8, ext, ".fbx"))
                .fbx
            else
                .unknown;
        }
    };

    id: Uuid,
    path: []u8,
    type: Type,
};

const ResourceStorage = std.AutoHashMap(Uuid, Resource);

const Self = @This();

var singleton: ?Self = null;

allocator: std.mem.Allocator,

resources: ResourceStorage,
resources_index: std.StringHashMap(Uuid),

resource_tree: ResourceNode,

pub const ResourceNode = struct {
    pub const Node = union(enum) {
        resource: Uuid,
        directory: []const u8,

        pub fn path(self: *const Node) ![]const u8 {
            return switch (self.*) {
                .resource => |id| getResourcePath(id),
                .directory => |d| d,
            };
        }

        pub fn uuid(self: *const Node) ?Uuid {
            return switch (self.*) {
                .resource => |id| id,
                .directory => null,
            };
        }

        pub fn eql(lhs: *const Node, rhs: *const Node) bool {
            if (std.meta.activeTag(lhs.*) != std.meta.activeTag(rhs.*)) {
                return false;
            }

            return switch (lhs.*) {
                .resource => |it| it.eql(rhs.resource),
                .directory => |it| std.mem.eql(u8, it, rhs.directory),
            };
        }

        pub fn clone(self: *Node, allocator: std.mem.Allocator) !Node {
            return switch (self.*) {
                .resource => |it| .{ .resource = it },
                .directory => |d| .{ .directory = try allocator.dupe(u8, d) },
            };
        }

        pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .resource => {},
                .directory => |d| allocator.free(d),
            }
        }
    };

    pub const GetOrPutResult = struct {
        value: *ResourceNode,
        found_existing: bool,
    };

    pub const DfsPreOrder = struct {
        pub const Result = struct {
            key_ptr: ?*[]const u8,
            event: DfsEvent,
        };
        pub const DfsEvent = union(enum) {
            enter: *ResourceNode,
            leave: *ResourceNode,
        };

        stack: std.ArrayList(Result),

        pub fn init(allocator: std.mem.Allocator, root: *ResourceNode) !DfsPreOrder {
            var self = DfsPreOrder{
                .stack = try std.ArrayList(Result).initCapacity(allocator, 1),
            };
            self.stack.appendAssumeCapacity(.{ .key_ptr = null, .event = .{ .enter = root } });
            return self;
        }

        pub fn deinit(self: *DfsPreOrder) void {
            self.stack.deinit();
        }

        pub fn next(self: *DfsPreOrder) !?Result {
            if (self.stack.items.len == 0) return null;

            const res = self.stack.pop();
            switch (res.event) {
                .enter => |node| {
                    var iter = node.children.iterator();
                    while (iter.next()) |it| {
                        try self.stack.append(.{ .key_ptr = it.key_ptr, .event = .{ .enter = it.value_ptr } });
                    }
                    try self.stack.append(.{ .key_ptr = res.key_ptr, .event = .{ .leave = node } });
                },
                else => {},
            }
            return res;
        }
    };

    pub const DfsPostOrder = struct {
        pub const Result = struct {
            key_ptr: ?*[]const u8,
            value_ptr: *ResourceNode,
        };
        stack: std.ArrayList(Result),

        pub fn init(allocator: std.mem.Allocator, root: *ResourceNode) !DfsPostOrder {
            var stack1 = std.ArrayList(Result).init(allocator);
            defer stack1.deinit();
            var stack2 = std.ArrayList(Result).init(allocator);
            try stack1.append(.{ .key_ptr = null, .value_ptr = root });

            while (stack1.items.len > 0) {
                const res = stack1.pop();
                try stack2.append(res);
                var iter = res.value_ptr.children.iterator();
                while (iter.next()) |child| {
                    try stack1.append(.{ .key_ptr = child.key_ptr, .value_ptr = child.value_ptr });
                }
            }

            return DfsPostOrder{
                .stack = stack2,
            };
        }

        pub fn deinit(self: *DfsPostOrder) void {
            self.stack.deinit();
        }

        pub fn next(self: *DfsPostOrder) !?Result {
            if (self.stack.items.len == 0) return null;

            return self.stack.pop();
        }
    };

    node: Node,
    children: std.StringArrayHashMap(ResourceNode),

    fn init(allocator: std.mem.Allocator, node: Node) ResourceNode {
        return .{
            .node = node,
            .children = std.StringArrayHashMap(ResourceNode).init(allocator),
        };
    }

    fn deinit(self: *ResourceNode) void {
        self.node.deinit(self.children.allocator);
        self.children.deinit();
    }

    pub fn dfs(self: *ResourceNode, allocator: std.mem.Allocator, comptime order: enum { pre, post }) !switch (order) {
        .pre => DfsPreOrder,
        .post => DfsPostOrder,
    } {
        return switch (order) {
            .pre => DfsPreOrder.init(allocator, self),
            .post => DfsPostOrder.init(allocator, self),
        };
    }

    pub fn find(self: *ResourceNode, relpath: []const u8) !?*ResourceNode {
        var segments = try std.fs.path.componentIterator(relpath);

        var node = self;

        while (segments.next()) |seg| {
            if (node.children.getPtr(seg.name)) |child| {
                node = child;
            } else {
                return null;
            }
        }
        return node;
    }

    pub fn getOrPut(self: *ResourceNode, relpath: []const u8) !GetOrPutResult {
        var segments = try std.fs.path.componentIterator(relpath);
        return self.getOrPutInternal(&segments);
    }

    fn getOrPutInternal(parent: *ResourceNode, segments: *std.fs.path.NativeComponentIterator) !GetOrPutResult {
        const segment = segments.next() orelse unreachable;
        const entry = try parent.children.getOrPut(segment.name);
        const has_next = segments.peekNext() != null;
        if (!entry.found_existing) {
            entry.key_ptr.* = try parent.children.allocator.dupe(u8, segment.name);
            if (has_next) {
                entry.value_ptr.* = ResourceNode.init(parent.children.allocator, .{ .directory = try parent.children.allocator.dupe(u8, segment.path) });
            }
        }

        return if (has_next)
            try entry.value_ptr.getOrPutInternal(segments)
        else
            GetOrPutResult{ .value = entry.value_ptr, .found_existing = entry.found_existing };
    }
};

fn instance() *Self {
    std.debug.assert(singleton != null);
    return &singleton.?;
}

pub fn init(allocator: std.mem.Allocator) !void {
    std.debug.assert(singleton == null);
    singleton = Self{
        .allocator = allocator,
        .resources = ResourceStorage.init(allocator),
        .resources_index = std.StringHashMap(Uuid).init(allocator),
        .resource_tree = ResourceNode.init(allocator, .{ .directory = try allocator.dupe(u8, "/") }),
    };

    {
        try register(.{ .urn = "3e21192b-6c22-4a4f-98ca-a4a43f675986", .path = "materials/default.mat", .category = "builtin" });
        try register(.{ .urn = "e732bb0c-19bb-492b-a79d-24fde85964d2", .path = "materials/none.mat", .category = "builtin" });
        try register(.{ .urn = "61de2700-0eac-4fd5-9c56-0bd5b6b9ba10", .path = "materials/pbr.mat", .category = "builtin" });
        try register(.{ .urn = "ad4bc22b-3765-4a9d-bab7-7984e101428a", .path = "lost_empire-RGBA.png", .category = "builtin" });
        try register(.{ .urn = "00923d64-c2ca-4d36-abbd-90b1fbde7a48", .path = "1x1.png", .category = "builtin" });
        try register(.{ .urn = "54dff348-3f93-429a-83c0-2d29b1ae00dd", .path = "1x1b.png", .category = "builtin" });
        try register(.{ .urn = "c4340d7a-caab-4925-965c-5ea71d8e447e", .path = "1x1h.png", .category = "builtin" });
        try register(.{ .urn = "ac6b9d14-0a56-458a-a7cc-fd36ede79468", .path = "lost_empire.obj", .category = "builtin" });
        try register(.{ .urn = "6d4f3849-e3d7-4cb0-b593-095a9afafb99", .path = "suzanne.obj", .category = "builtin" });
        try register(.{ .urn = "23400ade-52d7-416b-9679-884a49de1722", .path = "cube.obj", .category = "builtin" });
        try register(.{ .urn = "ab7151f0-1f77-4ae8-99ad-17695c6ab9de", .path = "sphere.obj", .category = "builtin" });
        try register(.{ .urn = "ac03092a-60d1-43d4-a4df-4c691aafae7b", .path = "bunny.obj", .category = "builtin" });
    }

    {
        try registerBuiltinShader("cf64bfc9-703c-43b0-9d01-c8032706872c", "tri_mesh.vert.glsl");
        try registerBuiltinShader("79d1e1cc-607d-491c-b2e8-d1d3a44bd6a4", "pbr.frag.glsl");
        try registerBuiltinShader("8b4db7d0-33a6-4f42-96cc-7b1d88566f27", "default_lit.frag.glsl");
        try registerBuiltinShader("9939ab1b-d72c-4463-b039-58211f2d6531", "textured_lit.frag.glsl");
    }

    {
        try register(.{ .urn = "2d02fa29-3740-4dfc-ab04-e77539734053", .path = "icons/play.png", .category = "editor" });
        try register(.{ .urn = "f4f6b6d6-66f8-4e8a-a575-3316b6a8a684", .path = "icons/pause.png", .category = "editor" });
        try register(.{ .urn = "b3cd9d64-6708-4d40-9f2b-9723df7bf3b1", .path = "icons/stop.png", .category = "editor" });
        try register(.{ .urn = "f23969d8-89cb-49cd-98fc-5ddec4955fc7", .path = "icons/fast-forward.png", .category = "editor" });
        try register(.{ .urn = "d63f3601-bf6e-456c-bb6e-be3b7692afa9", .path = "icons/folder.png", .category = "editor" });
        try register(.{ .urn = "a7838838-1942-46c9-83e5-49b949b70b26", .path = "icons/file.png", .category = "editor" });
        try register(.{ .urn = "93b26cfb-5269-4c8c-9269-74b60cbff456", .path = "icons/object.png", .category = "editor" });
        try register(.{ .urn = "ef77f971-4c34-4000-b0c4-9eab7ebafc8e", .path = "icons/move-tool.png", .category = "editor" });
        try register(.{ .urn = "e8480d10-cb60-4831-9796-f0823761d489", .path = "icons/rotate-tool.png", .category = "editor" });
        try register(.{ .urn = "b2c4cc39-1272-42b5-a40d-3e62d4cfbb12", .path = "icons/scale-tool.png", .category = "editor" });
        try register(.{ .urn = "4bf6d06c-2d96-4b12-8c20-f9a03a5152e1", .path = "icons/transform-tool.png", .category = "editor" });
        try register(.{ .urn = "eab7824b-f71c-4b90-a468-a5d91f4a3f7b", .path = "icons/close.png", .category = "editor" });
        try register(.{ .urn = "715b644d-f9a5-4aad-9cf9-6328cc849006", .path = "icons/browse.png", .category = "editor" });
        try register(.{ .urn = "48d0e511-cdaf-4111-8ffa-f7e31fbe9636", .path = "icons/home.png", .category = "editor" });
        try register(.{ .urn = "55cfea70-2c07-470f-a60c-7e8269ee2497", .path = "icons/editor.png", .category = "editor" });
        try register(.{ .urn = "dd8f5337-cf79-489e-849c-5331a044a578", .path = "icons/library.png", .category = "editor" });

        try register(.{ .urn = "72bb403a-8624-4541-bbaa-a85668340db1", .path = "icons/camera.png", .category = "editor" });
        try register(.{ .urn = "1e2e7db3-8b27-45b9-adf1-05e808175043", .path = "icons/mesh.png", .category = "editor" });
        try register(.{ .urn = "849d928a-a459-4df7-97c4-49877fba782c", .path = "icons/material.png", .category = "editor" });
        try register(.{ .urn = "e54f4382-dc55-4380-89db-0475bc02dd03", .path = "icons/point-light.png", .category = "editor" });
        try register(.{ .urn = "e17a74c7-cb8e-4cd3-90f2-d76ee499a13e", .path = "icons/sun.png", .category = "editor" });

        try register(.{ .urn = "682be1c4-a465-40ed-a4f0-31a07f2b1a20", .path = "icons/error.png", .category = "editor" });
        try register(.{ .urn = "a330bc08-999b-46df-a49b-f959a3b75b65", .path = "icons/warning.png", .category = "editor" });
        try register(.{ .urn = "376e63cc-21e1-4d05-bab7-ab5f71cd7ad3", .path = "icons/info.png", .category = "editor" });
        try register(.{ .urn = "7165bb42-7816-49a4-9b8b-ddb1aa1ee6a9", .path = "icons/debug.png", .category = "editor" });

        try register(.{ .urn = "1884f2b3-2689-4414-b0fe-b854e582c7f4", .path = "icons/error-mono.png", .category = "editor" });
        try register(.{ .urn = "ede4ab11-60c2-49e9-8792-22d26fc9cb50", .path = "icons/warning-mono.png", .category = "editor" });
        try register(.{ .urn = "fc2d47e6-9777-4c80-8c52-7d49fbec5d8a", .path = "icons/info-mono.png", .category = "editor" });
        try register(.{ .urn = "4306862e-7010-4063-8084-1cb6713ac701", .path = "icons/debug-mono.png", .category = "editor" });

        try register(.{ .urn = "9660e8f4-6809-4d57-9507-511117128bc3", .path = "icons/yume.png", .category = "editor" });
    }
}

pub fn reinit(new_allocator: std.mem.Allocator) !void {
    if (singleton != null) {
        try deinit();
        singleton = null;
    }
    try init(new_allocator);
}

pub fn deinit() !void {
    var self = instance();
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
        var iter = try Self.dfsPostOrder(self.allocator);
        defer iter.deinit();
        while (try iter.next()) |res| {
            if (res.key_ptr) |k| self.allocator.free(k.*);
            res.value_ptr.deinit();
        }
    }
}

pub fn getResourceId(path: []const u8) !Uuid {
    const self = instance();
    if (self.resources_index.get(path)) |id| {
        return id;
    }
    // TODO: add these to the index index
    var it = self.resources.iterator();
    while (it.next()) |next| {
        if (std.mem.eql(u8, next.value_ptr.path, path)) {
            return next.key_ptr.*;
        }
    }
    return error.ResourceNotFound;
}

pub fn getResourcePath(id: Uuid) ![]const u8 {
    if (instance().resources.get(id)) |r| {
        return r.path;
    } else {
        return error.ResourceNotFound;
    }
}

pub fn findResourceNode(path: []const u8) !?*ResourceNode {
    const self = instance();
    if (path.len == 1 and path[0] == '/') {
        return &self.resource_tree;
    }

    return self.resource_tree.find(path);
}

pub fn findResourceNodeByUri(uri: []const u8) !?*ResourceNode {
    const self = instance();
    if (uri.len == 1 and uri[0] == '/') {
        return &self.resource_tree;
    }
    var sfa = std.heap.stackFallback(2048, self.allocator);
    const allocator = sfa.get();

    const path = try parseUri(allocator, uri);
    defer allocator.free(path);

    return self.resource_tree.find(path);
}

// new path can be either relative to the root of the project or an absolute one
// results in the resource node getting moved and therefore invalidating the pointer,
// it returns the new pointer to the resource
pub fn move(id: Uuid, new_path: []const u8) !*ResourceNode {
    if (try utils.pathExists(new_path)) {
        return error.DestinationAlreadyExists;
    }
    const old_path = try getResourcePath(id);
    const old_dir = try std.fs.cwd().openDir(try std.fs.path.dirname(old_path));
    defer old_dir.close();
    const new_dir = try std.fs.cwd().openDir(try std.fs.path.dirname(new_path));
    defer new_dir.close();

    const old_basename = std.fs.path.basename(old_path);
    const new_basename = std.fs.path.basename(new_path);

    try std.fs.rename(old_dir, old_basename, new_dir, new_basename);
    @compileError("TODO");
}

pub fn readAssetAlloc(allocator: std.mem.Allocator, id: Uuid, max_bytes: usize) ![]u8 {
    log.debug("readAssetAlloc ({s}) :: {s}\n", .{ id.urn(), try getResourcePath(id) });
    var file = std.fs.cwd().openFile(try getResourcePath(id), .{}) catch return error.FailedToOpenResource;
    defer file.close();
    return file.readToEndAlloc(allocator, max_bytes) catch return error.FailedToReadResource;
}

pub fn dfsPreOrder(allocator: std.mem.Allocator) !ResourceNode.DfsPreOrder {
    return instance().*.resource_tree.dfs(allocator, .pre);
}

pub fn dfsPostOrder(allocator: std.mem.Allocator) !ResourceNode.DfsPostOrder {
    return instance().*.resource_tree.dfs(allocator, .post);
}

fn registerFromMeta(opts: struct {
    path: []const u8,
    category: []const u8 = "assets",
}) !void {
    const buf_size = 4096;
    var buf: [buf_size]u8 = undefined;

    const self = instance();
    var file = try std.fs.cwd().openFile(
        try std.fmt.bufPrint(&buf, "{s}{s}", .{ opts.path, yume_meta_extension_name }),
        .{},
    );
    defer file.close();
    const stats = try file.stat();
    if (stats.size > buf_size) return error.MetaFileIsTooBig;
    const len = try file.readAll(&buf);
    const content = buf[0..len];
    const meta = try std.json.parseFromSlice(Resource, self.allocator, content, .{});
    defer meta.deinit();

    try register(.{
        .urn = &meta.value.id.urn(),
        .path = meta.value.path,
        .category = opts.category,
    });
}

pub fn register(opts: struct {
    urn: []const u8,
    path: []const u8,
    category: []const u8 = "assets",
}) !void {
    const is_builtin = std.mem.eql(u8, opts.category, "builtin") or std.mem.eql(u8, opts.category, "editor");
    var self = instance();
    const id = try Uuid.fromUrnSlice(opts.urn);
    const editor_root = try Editor.rootDir(self.allocator);
    defer self.allocator.free(editor_root);

    const path = if (is_builtin)
        try std.fs.path.join(self.allocator, &[_][]const u8{ editor_root, "assets", opts.category, opts.path })
    else
        try self.allocator.dupe(u8, opts.path);
    errdefer self.allocator.free(path);

    if (!try utils.pathExists(path)) {
        return error.FileNotFound;
    }
    var uri: []const u8 = try std.fmt.allocPrint(self.allocator, "{s}://{s}", .{ opts.category, opts.path });
    const index_entry = try self.resources_index.getOrPut(uri);
    if (index_entry.found_existing) {
        self.allocator.free(uri);
        uri = index_entry.key_ptr.*;
        if (self.resources.fetchRemove(index_entry.value_ptr.*)) |it| {
            self.allocator.free(it.value.path);
        }

        log.warn("Duplicate resource being registered to the Assets Database, Replacing the old asset. {s}:{s}", .{ index_entry.value_ptr.urn(), uri });
    }

    const parsed_path = try parseUri(self.allocator, uri);
    defer self.allocator.free(parsed_path);
    const res_ptr = try self.resource_tree.getOrPut(parsed_path);
    std.debug.assert(!res_ptr.found_existing);
    try self.resources.put(id, Resource{
        .id = id,
        .path = path,
        .type = Resource.Type.fromExt(std.fs.path.extension(path)),
    });
    res_ptr.value.* = ResourceNode.init(self.allocator, .{ .resource = id });
    index_entry.value_ptr.* = id;
}

// TODO: shaders should register like any other resource
fn registerBuiltinShader(urn: []const u8, path: []const u8) !void {
    const self = instance();
    const id = try Uuid.fromUrnSlice(urn);
    const editor_root = try Editor.rootDir(self.allocator);
    defer self.allocator.free(editor_root);
    const pathspv = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ path[0 .. path.len - ".glsl".len], "spv" });
    defer self.allocator.free(pathspv);
    try self.resources.put(id, Resource{
        .id = id,
        .path = try std.fs.path.join(self.allocator, &[_][]const u8{ editor_root, "shaders", pathspv }),
        .type = .shader,
    });
    const uri = try std.fmt.allocPrint(self.allocator, "builtin://{s}", .{path});
    try self.resources_index.put(uri, id);
}

pub fn indexCwd() !void {
    const self = instance();
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();
    var iter = try dir.walk(allocator);
    defer iter.deinit();
    var files = std.StringHashMap(void).init(allocator);
    defer files.deinit();
    var metas = std.StringHashMap(void).init(allocator);
    defer metas.deinit();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }
        const fullpath = try allocator.dupe(u8, entry.path);
        const baseext = utils.baseExtensionSplit(fullpath);
        if (std.mem.eql(u8, baseext.ext, yume_meta_extension_name)) {
            if (files.fetchRemove(baseext.base)) |_| {
                try registerFromMeta(.{ .path = baseext.base });
            } else {
                try metas.put(baseext.base, {});
            }
        } else if (metas.fetchRemove(entry.path)) |_| {
            try registerFromMeta(.{ .path = baseext.base });
        } else {
            try files.put(entry.path, {});
        }
    }

    if (files.count() > 0) {
        log.err("some files are not marked with meta files TODO", .{});
    }

    if (metas.count() > 0) {
        var buf: [256]u8 = undefined;
        const result = try Editor.messageBox(.{
            .title = "Notice",
            .message = try std.fmt.bufPrintZ(
                &buf,
                "Found {d} meta files without the actual files, Do you want to delete them?",
                .{metas.count()},
            ),
        });
        if (result == 0) {
            log.err("TODO", .{});
        }
    }
}

pub fn parseUri(allocator: std.mem.Allocator, uri: []const u8) ![:0]const u8 {
    var end_of_protocol: usize = 0;
    for (0..uri.len) |i| {
        if (uri[i] == ':') {
            if (uri.len > i + 2 and uri[i + 1] == '/' and uri[i + 2] == '/') {
                end_of_protocol = i;
                break;
            }
        }
    }

    if (end_of_protocol == 0) {
        log.err("Invalid Uri: {s}", .{uri});
        return error.InvalidUri;
    }

    if (end_of_protocol + 3 >= uri.len) {
        return try std.fmt.allocPrintZ(allocator, "/{s}", .{uri[0..end_of_protocol]});
    } else {
        return try std.fmt.allocPrintZ(allocator, "/{s}/{s}", .{ uri[0..end_of_protocol], uri[end_of_protocol + 3 ..] });
    }
}
