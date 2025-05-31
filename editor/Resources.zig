const std = @import("std");

const Uuid = @import("yume").Uuid;
const utils = @import("yume").utils;
const Event = @import("yume").Event;
const Watch = @import("Watch.zig");

const GameApp = @import("yume").GameApp;
const assets = @import("yume").assets;
const shading = @import("yume").shading;

const collections = @import("yume").collections;

const Editor = @import("Editor.zig");

const log = std.log.scoped(.Resources);

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
        shader_stage,
        shader,
        mat,
        obj,
        fbx,
        png,

        pub fn fromExt(ext: []const u8) Type {
            const seql = std.mem.eql;
            return if (seql(u8, ext, ".scene"))
                .scene
            else if (seql(u8, ext, ".mat"))
                .mat
            else if (seql(u8, ext, ".obj"))
                .obj
            else if (seql(u8, ext, ".fbx"))
                .fbx
            else if (seql(u8, ext, ".png"))
                .png
            else if (seql(u8, ext, ".vert") or seql(u8, ext, ".frag"))
                .shader_stage
            else if (seql(u8, ext, ".shader"))
                .shader
            else
                .unknown;
        }

        pub fn fileIconUri(self: Type) [:0]const u8 {
            return switch (self) {
                inline else => |t| "editor://icons/filetypes/" ++ @tagName(t) ++ ".png",
            };
        }

        pub fn toAssetType(self: Type) assets.AssetType {
            return switch (self) {
                .unknown, .project, .shader_stage => .binary,
                .scene => .scene,
                .mat => .material,
                .shader => .shader,
                .obj, .fbx => .mesh,
                .png => .texture,
            };
        }
    };

    const max_buf_size = 4096;

    id: Uuid,
    uri: Uri,
    type: Type,

    pub inline fn path(self: *const Resource) [:0]const u8 {
        return self.uri.pathZ();
    }

    pub inline fn bufLoadPath(self: *const Resource, buf: []u8) ![:0]const u8 {
        return try self.bufFullpath(buf);
    }

    pub inline fn bufFullpath(self: *const Resource, buf: []u8) ![:0]const u8 {
        return self.uri.bufFullpath(buf);
    }

    pub fn bufMetaPath(self: *const Resource, buf: []u8) ![:0]const u8 {
        var fullpath_buf: [std.fs.max_path_bytes]u8 = undefined;
        const fullpath = try self.bufFullpath(&fullpath_buf);
        return std.fmt.bufPrintZ(buf, "{s}{s}", .{ fullpath, yume_meta_extension_name });
    }

    fn load(allocator: std.mem.Allocator, meta_path: []const u8) !Resource {
        var file = try std.fs.cwd().openFile(meta_path, .{});
        defer file.close();
        var buf: [max_buf_size]u8 = undefined;
        const stats = try file.stat();
        if (stats.size > max_buf_size) return error.MetaFileIsTooBig;
        const len = try file.readAll(&buf);
        const content = buf[0..len];
        return loadFromSlice(allocator, content);
    }

    fn loadFromSlice(allocator: std.mem.Allocator, slice: []const u8) !Resource {
        const parsed = try std.json.parseFromSlice(Resource, allocator, slice, .{});
        defer parsed.deinit();
        // TODO: use an explicit deserialization function to avoid leaks so this extra allocation can be removed
        return parsed.value.clone(allocator);
    }

    fn save(self: *const Resource, allocator: std.mem.Allocator, create_if_missing: bool) !void {
        var buf: [1024]u8 = undefined;
        const meta_path = try self.bufMetaPath(&buf);
        var file = f: {
            if (create_if_missing) {
                std.log.debug("{s}", .{meta_path});
                break :f try std.fs.cwd().createFile(meta_path, .{ .truncate = true });
            } else {
                const file = try std.fs.cwd().openFile(meta_path, .{ .mode = .read_write });
                errdefer file.close();
                var content_buf: [max_buf_size]u8 = undefined;
                const stats = try file.stat();
                if (stats.size > max_buf_size) return error.MetaFileIsTooBig;
                const len = try file.readAll(&content_buf);
                const content = content_buf[0..len];
                var on_disk = try loadFromSlice(allocator, content);
                defer on_disk.deinit(allocator);
                if (on_disk.eql(self)) {
                    file.close();
                    return;
                }
                try file.seekTo(0);
                try file.setEndPos(0);
                break :f file;
            }
        };
        try std.json.stringify(self, .{ .whitespace = .indent_4 }, file.writer());
        defer file.close();
    }

    pub fn eql(
        lhs: *const Resource,
        rhs: *const Resource,
    ) bool {
        return lhs.id.eql(rhs.id) and
            lhs.uri.eql(&rhs.uri) and
            lhs.type == rhs.type;
    }

    pub fn clone(self: *const Resource, allocator: std.mem.Allocator) !Resource {
        return .{
            .id = self.id,
            .type = self.type,
            .uri = try self.uri.clone(allocator),
        };
    }

    pub fn deinit(self: *Resource, allocator: std.mem.Allocator) void {
        self.uri.deinit(allocator);
    }
};

const ResourceStorage = std.AutoHashMap(Uuid, Resource);

pub const OnRegisterEvent = Event(.{*const ResourceNode});
pub const OnUnregisterEvent = Event(.{*const ResourceNode});
pub const OnReinitEvent = Event(.{});

const Self = @This();

var singleton: ?Self = null;

allocator: std.mem.Allocator,

resources: ResourceStorage,
resources_index: std.StringHashMap(Uuid), // key is the resource URI

resource_tree: ResourceNode,

loaded_shader_defs: std.AutoHashMap(Uuid, *shading.Shader.Def),
loaded_material_defs: std.AutoHashMap(Uuid, *shading.Material.Def),

watcher: ?*Watch = null,
watcher_counter: f32 = 0,

on_register: OnRegisterEvent.List,
on_unregister: OnUnregisterEvent.List,
on_reinit: OnReinitEvent.List,

pub const ResourceNode = struct {
    pub const Node = union(enum) {
        root,
        resource: Uuid,
        directory: Uri,

        pub fn path(self: *const Node) ![:0]const u8 {
            return switch (self.*) {
                .root => return error.RootNodeHasNoPath,
                .resource => |id| getResourcePath(id),
                .directory => |d| d.pathZ(),
            };
        }

        pub fn uri(self: *const Node) !*const Uri {
            return switch (self.*) {
                .root => return error.RootNodeHasNoUri,
                .resource => |id| &(getResourcePtr(id) orelse return error.ResourceNotFound).uri,
                .directory => |*d| d,
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
                .root => true,
                .resource => |it| it.eql(rhs.resource),
                .directory => |it| it.eql(&rhs.directory),
            };
        }

        pub fn clone(self: *const Node, allocator: std.mem.Allocator) !Node {
            return switch (self.*) {
                .root => .root,
                .resource => |it| .{ .resource = it },
                .directory => |d| .{ .directory = try d.clone(allocator) },
            };
        }

        pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .root, .resource => {},
                .directory => |*d| d.deinit(allocator),
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
            key_ptr: ?*[:0]const u8,
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
    children: collections.StringSentinelArrayHashMap(0, ResourceNode),

    fn init(allocator: std.mem.Allocator, node: Node) ResourceNode {
        return .{
            .node = node,
            .children = collections.StringSentinelArrayHashMap(0, ResourceNode).init(allocator),
        };
    }

    fn deinit(self: *ResourceNode, recursive: bool) void {
        self.node.deinit(self.children.allocator);
        {
            var iter = self.children.iterator();
            if (recursive) {
                while (iter.next()) |it| {
                    it.value_ptr.deinit(true);
                }
            }
            self.children.deinit();
        }
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
            if (node.children.getPtrAdapted(seg.name, collections.ArrayHashMapStringAdaptedContext)) |child| {
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
        const allocator = parent.children.allocator;
        const segment = segments.next() orelse unreachable;
        const name = try allocator.dupeZ(u8, segment.name);
        const entry = try parent.children.getOrPut(name);
        const has_next = segments.peekNext() != null;
        if (!entry.found_existing) {
            if (has_next) {
                if (parent.node == .root) {
                    entry.value_ptr.* = ResourceNode.init(allocator, .{
                        .directory = Uri.fromOwnedSliceWithProtocolLen(
                            try std.fmt.allocPrintZ(allocator, "{s}://", .{name}),
                            name.len,
                        ),
                    });
                } else {
                    entry.value_ptr.* = ResourceNode.init(allocator, .{
                        .directory = try (try parent.node.uri()).join(allocator, &[_][]const u8{name}),
                    });
                }
            }
        } else {
            allocator.free(name);
        }

        return if (has_next)
            try entry.value_ptr.getOrPutInternal(segments)
        else
            GetOrPutResult{ .value = entry.value_ptr, .found_existing = entry.found_existing };
    }
};

const ResourceTree = struct {};

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
        .resource_tree = ResourceNode.init(allocator, .root),

        .loaded_shader_defs = std.AutoHashMap(Uuid, *shading.Shader.Def).init(allocator),
        .loaded_material_defs = std.AutoHashMap(Uuid, *shading.Material.Def).init(allocator),

        .watcher = if (Watch.supported_platform) try Watch.init(allocator, ".") else null,

        .on_register = OnRegisterEvent.List.init(allocator),
        .on_unregister = OnUnregisterEvent.List.init(allocator),
        .on_reinit = OnReinitEvent.List.init(allocator),
    };

    errdefer deinit() catch {};

    { // builtin assets
        const cat = "builtin";
        _ = try register(.{ .urn = "3e21192b-6c22-4a4f-98ca-a4a43f675986", .path = "materials/default.mat", .category = cat });
        _ = try register(.{ .urn = "e732bb0c-19bb-492b-a79d-24fde85964d2", .path = "materials/none.mat", .category = cat });
        _ = try register(.{ .urn = "61de2700-0eac-4fd5-9c56-0bd5b6b9ba10", .path = "materials/pbr.mat", .category = cat });
        _ = try register(.{ .urn = "ad4bc22b-3765-4a9d-bab7-7984e101428a", .path = "lost_empire-RGBA.png", .category = cat });
        _ = try register(.{ .urn = "00923d64-c2ca-4d36-abbd-90b1fbde7a48", .path = "1x1.png", .category = cat });
        _ = try register(.{ .urn = "54dff348-3f93-429a-83c0-2d29b1ae00dd", .path = "1x1b.png", .category = cat });
        _ = try register(.{ .urn = "c4340d7a-caab-4925-965c-5ea71d8e447e", .path = "1x1h.png", .category = cat });
        _ = try register(.{ .urn = "ac6b9d14-0a56-458a-a7cc-fd36ede79468", .path = "lost_empire.obj", .category = cat });
        _ = try register(.{ .urn = "6d4f3849-e3d7-4cb0-b593-095a9afafb99", .path = "suzanne.obj", .category = cat });
        _ = try register(.{ .urn = "23400ade-52d7-416b-9679-884a49de1722", .path = "cube.obj", .category = cat });
        _ = try register(.{ .urn = "ab7151f0-1f77-4ae8-99ad-17695c6ab9de", .path = "sphere.obj", .category = cat });
    }

    { // builtin shaders
        const cat = "builtin-shaders";
        _ = try register(.{ .urn = "cf64bfc9-703c-43b0-9d01-c8032706872c", .path = "simple.vert", .category = cat });
        _ = try register(.{ .urn = "79d1e1cc-607d-491c-b2e8-d1d3a44bd6a4", .path = "pbr.frag", .category = cat });
        _ = try register(.{ .urn = "361d3e88-c823-41fa-821d-5a7811af41ce", .path = "pbr.shader", .category = cat });
        _ = try register(.{ .urn = "8b4db7d0-33a6-4f42-96cc-7b1d88566f27", .path = "default_unlit.frag", .category = cat });
        _ = try register(.{ .urn = "7166c8c1-9f74-4093-b626-e226d4ce63ff", .path = "default_unlit.shader", .category = cat });
        _ = try register(.{ .urn = "9939ab1b-d72c-4463-b039-58211f2d6531", .path = "textured_unlit.frag", .category = cat });
        _ = try register(.{ .urn = "603b93fe-9d75-48af-88f5-3c2af8e72b0b", .path = "textured_unlit.shader", .category = cat });
    }

    { // editor resources
        _ = try register(.{ .urn = "2d02fa29-3740-4dfc-ab04-e77539734053", .path = "icons/play.png", .category = "editor" });
        _ = try register(.{ .urn = "f4f6b6d6-66f8-4e8a-a575-3316b6a8a684", .path = "icons/pause.png", .category = "editor" });
        _ = try register(.{ .urn = "b3cd9d64-6708-4d40-9f2b-9723df7bf3b1", .path = "icons/stop.png", .category = "editor" });
        _ = try register(.{ .urn = "f23969d8-89cb-49cd-98fc-5ddec4955fc7", .path = "icons/fast-forward.png", .category = "editor" });
        _ = try register(.{ .urn = "d63f3601-bf6e-456c-bb6e-be3b7692afa9", .path = "icons/folder.png", .category = "editor" });
        _ = try register(.{ .urn = "a7838838-1942-46c9-83e5-49b949b70b26", .path = "icons/file.png", .category = "editor" });
        _ = try register(.{ .urn = "93b26cfb-5269-4c8c-9269-74b60cbff456", .path = "icons/object.png", .category = "editor" });
        _ = try register(.{ .urn = "ef77f971-4c34-4000-b0c4-9eab7ebafc8e", .path = "icons/move-tool.png", .category = "editor" });
        _ = try register(.{ .urn = "e8480d10-cb60-4831-9796-f0823761d489", .path = "icons/rotate-tool.png", .category = "editor" });
        _ = try register(.{ .urn = "b2c4cc39-1272-42b5-a40d-3e62d4cfbb12", .path = "icons/scale-tool.png", .category = "editor" });
        _ = try register(.{ .urn = "4bf6d06c-2d96-4b12-8c20-f9a03a5152e1", .path = "icons/transform-tool.png", .category = "editor" });
        _ = try register(.{ .urn = "eab7824b-f71c-4b90-a468-a5d91f4a3f7b", .path = "icons/close.png", .category = "editor" });
        _ = try register(.{ .urn = "715b644d-f9a5-4aad-9cf9-6328cc849006", .path = "icons/browse.png", .category = "editor" });
        _ = try register(.{ .urn = "dc031587-841a-4665-99f2-65be5007a1ab", .path = "icons/search.png", .category = "editor" });
        _ = try register(.{ .urn = "48d0e511-cdaf-4111-8ffa-f7e31fbe9636", .path = "icons/home.png", .category = "editor" });
        _ = try register(.{ .urn = "55cfea70-2c07-470f-a60c-7e8269ee2497", .path = "icons/editor.png", .category = "editor" });
        _ = try register(.{ .urn = "dd8f5337-cf79-489e-849c-5331a044a578", .path = "icons/library.png", .category = "editor" });

        _ = try register(.{ .urn = "72bb403a-8624-4541-bbaa-a85668340db1", .path = "icons/camera.png", .category = "editor" });
        _ = try register(.{ .urn = "1e2e7db3-8b27-45b9-adf1-05e808175043", .path = "icons/mesh.png", .category = "editor" });
        _ = try register(.{ .urn = "849d928a-a459-4df7-97c4-49877fba782c", .path = "icons/material.png", .category = "editor" });
        _ = try register(.{ .urn = "e54f4382-dc55-4380-89db-0475bc02dd03", .path = "icons/point-light.png", .category = "editor" });
        _ = try register(.{ .urn = "e17a74c7-cb8e-4cd3-90f2-d76ee499a13e", .path = "icons/sun.png", .category = "editor" });

        _ = try register(.{ .urn = "6be190a7-d244-4d7e-976b-0f3d4ab622d1", .path = "icons/list.png", .category = "editor" });
        _ = try register(.{ .urn = "28e44106-f545-4fa3-9ce9-387dbdee4f57", .path = "icons/grid.png", .category = "editor" });
        _ = try register(.{ .urn = "841c688a-b205-4db2-b6a8-6bed87b3e46c", .path = "icons/filter.png", .category = "editor" });

        _ = try register(.{ .urn = "d16bc474-c896-4aec-b35d-fcdfac790fbb", .path = "icons/filetypes/fbx.png", .category = "editor" });
        _ = try register(.{ .urn = "825643b1-6054-49a8-8ec1-fce29767e512", .path = "icons/filetypes/mat.png", .category = "editor" });
        _ = try register(.{ .urn = "38d6820e-c8e5-4374-9e8a-4196c5ab0802", .path = "icons/filetypes/obj.png", .category = "editor" });
        _ = try register(.{ .urn = "6a6ef862-387e-41f9-864f-6e764213f60b", .path = "icons/filetypes/png.png", .category = "editor" });
        _ = try register(.{ .urn = "88bbd334-c48e-489f-b5e7-a9c035220db5", .path = "icons/filetypes/project.png", .category = "editor" });
        _ = try register(.{ .urn = "8467cf1a-51fa-416f-8fd8-e5f3adc5e18c", .path = "icons/filetypes/scene.png", .category = "editor" });
        _ = try register(.{ .urn = "c77e42f5-0c63-4046-b99f-220e270bd7bd", .path = "icons/filetypes/shader.png", .category = "editor" });

        _ = try register(.{ .urn = "682be1c4-a465-40ed-a4f0-31a07f2b1a20", .path = "icons/error.png", .category = "editor" });
        _ = try register(.{ .urn = "a330bc08-999b-46df-a49b-f959a3b75b65", .path = "icons/warning.png", .category = "editor" });
        _ = try register(.{ .urn = "376e63cc-21e1-4d05-bab7-ab5f71cd7ad3", .path = "icons/info.png", .category = "editor" });
        _ = try register(.{ .urn = "7165bb42-7816-49a4-9b8b-ddb1aa1ee6a9", .path = "icons/debug.png", .category = "editor" });

        _ = try register(.{ .urn = "1884f2b3-2689-4414-b0fe-b854e582c7f4", .path = "icons/error-mono.png", .category = "editor" });
        _ = try register(.{ .urn = "ede4ab11-60c2-49e9-8792-22d26fc9cb50", .path = "icons/warning-mono.png", .category = "editor" });
        _ = try register(.{ .urn = "fc2d47e6-9777-4c80-8c52-7d49fbec5d8a", .path = "icons/info-mono.png", .category = "editor" });
        _ = try register(.{ .urn = "4306862e-7010-4063-8084-1cb6713ac701", .path = "icons/debug-mono.png", .category = "editor" });

        _ = try register(.{ .urn = "cfccdd2d-3e72-4133-b42f-d988d5602da8", .path = "icons/image-small.png", .category = "editor" });
        _ = try register(.{ .urn = "a2d609ba-86f0-493d-854d-6f2f1279e932", .path = "icons/color-picker-small.png", .category = "editor" });
        _ = try register(.{ .urn = "68637dd0-97df-4af4-8386-eeeee9e6815f", .path = "icons/numpad-small.png", .category = "editor" });

        _ = try register(.{ .urn = "9660e8f4-6809-4d57-9507-511117128bc3", .path = "icons/yume.png", .category = "editor" });
    }
}

pub fn reinit(new_allocator: std.mem.Allocator) !void {
    var reg_cbs = OnRegisterEvent.List.init(new_allocator);
    errdefer reg_cbs.deinit();
    var unreg_cbs = OnRegisterEvent.List.init(new_allocator);
    errdefer unreg_cbs.deinit();
    var reinit_cbs = OnReinitEvent.List.init(new_allocator);
    errdefer reinit_cbs.deinit();

    if (singleton) |s| {
        try reg_cbs.copyFrom(&s.on_register);
        try unreg_cbs.copyFrom(&s.on_unregister);
        try reinit_cbs.copyFrom(&s.on_reinit);
        try deinit();
        singleton = null;
    }
    try init(new_allocator);

    singleton.?.on_register.deinit();
    singleton.?.on_register = reg_cbs;

    singleton.?.on_unregister.deinit();
    singleton.?.on_unregister = unreg_cbs;

    singleton.?.on_reinit.deinit();
    singleton.?.on_reinit = reinit_cbs;
    singleton.?.on_reinit.fire(.{});
}

pub fn deinit() !void {
    var self = instance();
    if (self.watcher) |w| w.deinit();
    self.on_register.deinit();
    self.on_unregister.deinit();
    self.on_reinit.deinit();

    {
        var it = self.loaded_shader_defs.valueIterator();
        while (it.next()) |def| {
            def.*.deinit(self.allocator);
            self.allocator.destroy(def.*);
        }
        self.loaded_shader_defs.deinit();
    }

    {
        var it = self.loaded_material_defs.valueIterator();
        while (it.next()) |def| {
            def.*.deinit(self.allocator);
            self.allocator.destroy(def.*);
        }
        self.loaded_material_defs.deinit();
    }

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
            kv.value_ptr.deinit(self.allocator);
        }
    }
    self.resources.deinit();

    {
        var iter = try Self.dfsPostOrder(self.allocator);
        defer iter.deinit();
        while (try iter.next()) |res| {
            if (res.key_ptr) |k| self.allocator.free(k.*);
            res.value_ptr.deinit(false);
        }
    }
}

pub fn resourceExists(id: Uuid) bool {
    return instance().resources.contains(id);
}

pub fn resourceExistsByUri(uri: []const u8) bool {
    return instance().resources_index.contains(uri);
}

// clones the resource meta data using the provided allocator
pub fn getResource(allocator: std.mem.Allocator, id: Uuid) !?Resource {
    if (instance().resources.get(id)) |r| {
        return try r.clone(allocator);
    } else {
        return error.ResourceNotFound;
    }
}

fn getResourcePtr(id: Uuid) ?*Resource {
    return instance().resources.getPtr(id);
}

pub fn getResourceId(uri: []const u8) !Uuid {
    const self = instance();
    if (self.resources_index.get(uri)) |id| {
        return id;
    }
    return error.ResourceNotFound;
}

pub fn getAssetHandle(
    uri: []const u8,
    comptime opts: struct { expect: ?assets.AssetType = null },
) !if (opts.expect) |expect| expect.HandleType() else assets.AssetHandle {
    const self = instance();
    if (self.resources_index.get(uri)) |id| {
        const handle = assets.AssetHandle{
            .uuid = id,
            .type = getResourcePtr(id).?.type.toAssetType(),
        };
        return if (comptime opts.expect) |expect| handle.unbox(expect) else handle;
    }
    return error.ResourceNotFound;
}

pub fn getResourcePath(id: Uuid) ![:0]const u8 {
    if (instance().resources.get(id)) |r| {
        return r.path();
    } else {
        return error.ResourceNotFound;
    }
}

pub fn bufResourceFullpath(id: Uuid, buf: []u8) ![:0]const u8 {
    if (instance().resources.get(id)) |r| {
        return r.bufFullpath(buf);
    } else {
        return error.ResourceNotFound;
    }
}

pub fn getResourceFullpath(id: Uuid) ![:0]const u8 {
    if (instance().resources.get(id)) |r| {
        return r.path();
    } else {
        return error.ResourceNotFound;
    }
}

pub fn getResourceType(id: Uuid) !Resource.Type {
    if (instance().resources.get(id)) |r| {
        return r.type;
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

pub fn findResourceNodeByUri(uri: *const Uri) !?*ResourceNode {
    const self = instance();
    if (uri.isRoot()) {
        return &self.resource_tree;
    }
    var sfa = std.heap.stackFallback(2048, self.allocator);
    const allocator = sfa.get();

    const path = try parseUri(allocator, uri.span());
    defer allocator.free(path);

    return findResourceNode(path);
}

// both new and old paths are relative to the project's root
pub fn move(old_path: []const u8, new_path: []const u8) !void {
    if (try utils.pathExists(new_path)) {
        return error.DestinationAlreadyExists;
    }
    var old_dir = try std.fs.cwd().openDir(std.fs.path.dirname(old_path) orelse ".", .{});
    defer old_dir.close();
    var new_dir = try std.fs.cwd().openDir(std.fs.path.dirname(new_path) orelse ".", .{});
    defer new_dir.close();

    const old_basename = std.fs.path.basename(old_path);
    const new_basename = std.fs.path.basename(new_path);

    var old_meta_buf: [std.fs.max_path_bytes]u8 = undefined;
    const old_meta = try std.fmt.bufPrintZ(&old_meta_buf, "{s}{s}", .{ old_path, yume_meta_extension_name });
    var new_meta_buf: [std.fs.max_path_bytes]u8 = undefined;
    const new_meta = try std.fmt.bufPrintZ(&new_meta_buf, "{s}{s}", .{ new_path, yume_meta_extension_name });

    try std.fs.rename(old_dir, old_basename, new_dir, new_basename);
    if (try utils.pathExists(old_meta) and !try utils.pathExists(new_meta)) {
        try std.fs.rename(
            old_dir,
            std.fs.path.basename(old_meta),
            new_dir,
            std.fs.path.basename(new_meta),
        );
    }
}

pub fn readAssetAlloc(allocator: std.mem.Allocator, id: Uuid, max_bytes: usize) ![]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const resource = getResourcePtr(id) orelse return error.ResourceNotFound;
    const fullpath = resource.bufLoadPath(&buf) catch return error.FailedToOpenResource;
    log.debug("readAssetAlloc ({s}) :: {s}", .{ id.urn(), fullpath });
    var file = std.fs.cwd().openFile(fullpath, .{}) catch return error.FailedToOpenResource;
    defer file.close();
    return file.readToEndAlloc(allocator, max_bytes) catch return error.FailedToReadResource;
}

pub fn getShaderDef(id: Uuid) !*const shading.Shader.Def {
    return try getShaderDefMut(id);
}

pub fn getShaderDefMut(id: Uuid) !*shading.Shader.Def {
    const max_bytes = 20_000;
    const self = instance();
    const gop = try self.loaded_shader_defs.getOrPut(id);
    if (gop.found_existing) {
        return gop.value_ptr.*;
    }
    errdefer self.loaded_shader_defs.removeByPtr(gop.key_ptr);

    const json = try readAssetAlloc(self.allocator, id, max_bytes);
    defer self.allocator.free(json);

    gop.value_ptr.* = try self.allocator.create(shading.Shader.Def);
    errdefer gop.value_ptr.*.deinit(self.allocator);

    gop.value_ptr.*.* = std.json.parseFromSliceLeaky(
        shading.Shader.Def,
        self.allocator,
        json,
        .{},
    ) catch return error.FailedToParseResource;

    return gop.value_ptr.*;
}

pub fn getMaterialDef(id: Uuid) !*const shading.Material.Def {
    return try getMaterialDefMut(id);
}

pub fn getMaterialDefMut(id: Uuid) !*shading.Material.Def {
    const max_bytes = 20_000;
    const self = instance();
    const gop = try self.loaded_material_defs.getOrPut(id);
    if (gop.found_existing) {
        return gop.value_ptr.*;
    }
    errdefer self.loaded_material_defs.removeByPtr(gop.key_ptr);

    const json = try readAssetAlloc(self.allocator, id, max_bytes);
    defer self.allocator.free(json);

    gop.value_ptr.* = try self.allocator.create(shading.Material.Def);
    errdefer gop.value_ptr.*.deinit(self.allocator);

    gop.value_ptr.*.* = std.json.parseFromSliceLeaky(
        shading.Material.Def,
        self.allocator,
        json,
        .{},
    ) catch return error.FailedToParseResource;

    return gop.value_ptr.*;
}

pub fn dfsPreOrder(allocator: std.mem.Allocator) !ResourceNode.DfsPreOrder {
    return instance().*.resource_tree.dfs(allocator, .pre);
}

pub fn dfsPostOrder(allocator: std.mem.Allocator) !ResourceNode.DfsPostOrder {
    return instance().*.resource_tree.dfs(allocator, .post);
}

fn registerFromMeta(opts: struct {
    path: []const u8,
    category: []const u8 = "project",
    update_uuid_if_exists: bool = false,
}) !Uuid {
    var buf: [Resource.max_buf_size]u8 = undefined;

    const self = instance();
    var meta = try Resource.load(
        self.allocator,
        try std.fmt.bufPrint(&buf, "{s}{s}", .{ opts.path, yume_meta_extension_name }),
    );
    defer meta.deinit(self.allocator);

    const exists = resourceExists(meta.id);

    if (!std.mem.eql(u8, meta.path(), opts.path)) {
        log.debug("updating meta path? {s} == {s}", .{ meta.path(), opts.path });
        if (exists and !try utils.pathExists(meta.path())) { // it might be a moved resource
            log.debug("already loaded", .{});
            const res_ptr = getResourcePtr(meta.id).?;
            try res_ptr.uri.setPath(self.allocator, opts.path);
            return res_ptr.id;
        }
        try meta.uri.setPath(self.allocator, opts.path);
    }
    log.debug("updating meta path? {s} uri {s}", .{ meta.path(), meta.uri });

    if (opts.update_uuid_if_exists and exists) {
        meta.id = Uuid.new();
    }

    return try register(.{
        .urn = &meta.id.urn(),
        .path = meta.path(),
        .type = meta.type,
        .category = opts.category,
        .ensure_meta = false,
    });
}

pub fn register(opts: struct {
    urn: []const u8,
    path: []const u8,
    type: ?Resource.Type = null,
    category: []const u8 = "project",
    ensure_meta: bool = true,
}) !Uuid {
    const is_builtin = std.mem.eql(u8, opts.category, "builtin") or std.mem.eql(u8, opts.category, "builtin-shaders") or std.mem.eql(u8, opts.category, "editor");
    var self = instance();
    const id = try Uuid.fromUrnSlice(opts.urn);
    const editor_root = try Editor.rootDir(self.allocator);
    defer self.allocator.free(editor_root);

    const path = if (is_builtin)
        try std.fs.path.joinZ(self.allocator, &[_][]const u8{ editor_root, "resources", opts.category, opts.path })
    else
        try self.allocator.dupeZ(u8, opts.path);
    defer self.allocator.free(path);

    if (!try utils.pathExists(path)) {
        log.err("Resource not found: {s}", .{path});
        return error.FileNotFound;
    }
    var uri: []const u8 = try std.fmt.allocPrint(self.allocator, "{s}://{s}", .{ opts.category, opts.path });
    const index_entry = try self.resources_index.getOrPut(uri);
    if (index_entry.found_existing) {
        self.allocator.free(uri);
        uri = index_entry.key_ptr.*;
        if (self.resources.fetchRemove(index_entry.value_ptr.*)) |it| {
            var val = it.value;
            val.deinit(self.allocator);
        }

        log.warn("Duplicate resource being registered to the Resource index, Replacing the old asset. {s}:{s}", .{ index_entry.value_ptr.urn(), uri });
    }

    const parsed_path = try parseUri(self.allocator, uri);
    defer self.allocator.free(parsed_path);
    const res_node = try self.resource_tree.getOrPut(parsed_path);
    std.debug.assert(!res_node.found_existing);
    const res_ptr = try self.resources.getOrPut(id);
    std.debug.assert(!res_ptr.found_existing);
    res_ptr.value_ptr.* = Resource{
        .id = id,
        .uri = try Uri.initWithProtocolLen(self.allocator, uri, opts.category.len),
        .type = opts.type orelse Resource.Type.fromExt(std.fs.path.extension(path)),
    };
    res_node.value.* = ResourceNode.init(self.allocator, .{ .resource = id });
    index_entry.value_ptr.* = id;
    res_ptr.value_ptr.save(self.allocator, opts.ensure_meta) catch |err| if (opts.ensure_meta) return err else log.warn("something went wrong while saving the resource's meta {}", .{err});

    self.on_register.fire(.{res_node.value});

    return res_ptr.key_ptr.*;
}

pub fn onRegister() *OnRegisterEvent.List {
    return &instance().on_register;
}

pub fn onUnregister() *OnUnregisterEvent.List {
    return &instance().on_unregister;
}

pub fn onReinit() *OnReinitEvent.List {
    return &instance().on_reinit;
}

// if resource isn't a project asset this function has undefined behavior.
// builtin resources aren't meant to be unregistered
fn unregister(id: Uuid) !void {
    var self = instance();
    const res_ptr = getResourcePtr(id) orelse return error.ResourceNotFound;
    std.log.debug("{s}", .{res_ptr.path()});

    const parent_uri_slice = res_ptr.uri.parent() orelse res_ptr.uri.protocolWithSeperator();
    var parent_uri = try Uri.parse(self.allocator, parent_uri_slice);
    defer parent_uri.deinit(self.allocator);

    var parent = try findResourceNodeByUri(&parent_uri) orelse return error.UnexpectedError;

    const index_kv = self.resources_index.fetchRemove(res_ptr.uri.span()) orelse {
        log.debug("Failed to unregister uri: {s}", .{res_ptr.uri});
        return error.IllegalUnregisterOperation;
    };
    self.allocator.free(index_kv.key);

    var rnode = parent.children.fetchOrderedRemoveAdapted(
        std.fs.path.basename(res_ptr.path()),
        collections.ArrayHashMapStringAdaptedContext,
    ) orelse
        return error.UnexpectedError;

    self.allocator.free(rnode.key);
    rnode.value.deinit(true);

    var it = self.resources.fetchRemove(id) orelse return error.UnexpectedError;

    it.value.deinit(self.allocator);
}

pub fn indexCwd() !void {
    const self = instance();
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    var files = std.StringHashMap(void).init(allocator);
    defer files.deinit();
    var metas = std.StringHashMap(void).init(allocator);
    defer metas.deinit();
    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const normalized = utils.normalizePathSep(try allocator.dupe(u8, entry.path));
                const baseext = utils.baseExtensionSplit(normalized);
                if (std.mem.eql(u8, baseext.ext, yume_meta_extension_name)) {
                    if (files.fetchRemove(baseext.base)) |_| {
                        _ = try registerFromMeta(.{ .path = baseext.base });
                    } else {
                        try metas.put(baseext.base, {});
                    }
                } else if (metas.fetchRemove(normalized)) |_| {
                    _ = try registerFromMeta(.{ .path = baseext.base });
                } else {
                    try files.put(normalized, {});
                }
            },
            .directory => { // TODO: perhaps directories should have a register method as well?
                var dir_node = ResourceNode.init(self.allocator, .{
                    .directory = Uri.fromOwnedSliceWithProtocolLen(
                        try std.fmt.allocPrintZ(self.allocator, "project://{s}", .{entry.path}),
                        "project".len,
                    ),
                });

                const tmp_path = try std.fmt.allocPrintZ(self.allocator, "/project/{s}", .{entry.path}); // TODO: remove me
                defer self.allocator.free(tmp_path);
                const gop = try self.resource_tree.getOrPut(tmp_path);
                if (gop.found_existing) {
                    dir_node.deinit(false);
                } else {
                    gop.value.* = dir_node;
                    self.on_register.fire(.{gop.value});
                }
            },
            else => {},
        }
    }

    {
        var iter = files.iterator();
        while (iter.next()) |it| {
            _ = try register(.{ .urn = &Uuid.new().urn(), .path = it.key_ptr.* });
        }
    }

    {
        var iter = metas.iterator();
        while (iter.next()) |it| {
            try std.fs.cwd().deleteFile(it.key_ptr.*);
        }
    }
}

pub fn parseUri(allocator: std.mem.Allocator, uri: []const u8) ![:0]const u8 {
    // fast path for URIs from the root `:://`
    // e.g. `:://project/x/y/z` over `project://x/y/z`
    if (std.mem.eql(u8, uri[0..":://".len], ":://")) {
        return try std.fmt.allocPrintZ(allocator, "/{s}", .{uri[":://".len..]});
    }

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

pub fn update(dt: f32, ctx: *GameApp) void {
    const ins = instance();
    ins.watcher_counter += dt;
    if (!ctx.isFocused()) {
        return;
    }

    if (ins.watcher) |w| {
        if (ins.watcher_counter > 1) {
            ins.watcher_counter = 0;
            w.dispatch(Self, &struct {
                fn f(self: *Self, event: Watch.Event) void {
                    log.debug("resource watch event {s}({s})", .{ @tagName(event), event.path() });
                    Self.onWatchEvent(self, event) catch |err| log.err(
                        "watching project encountered an error {}",
                        .{err},
                    );
                }
            }.f, ins) catch |e| log.err("Watch error: {}", .{e});
        }
    }
}

fn onWatchEvent(self: *Self, event: Watch.Event) !void {
    var sfa = std.heap.stackFallback(4096, self.allocator);
    const allocator = sfa.get();

    dir_ev: {
        var uri = Uri.fromOwnedSliceWithProtocolLen(
            try std.fmt.allocPrintZ(self.allocator, "project://{s}", .{event.path()}),
            "project".len,
        );
        defer uri.deinit(self.allocator);

        switch (event) {
            .add, .rename_new => |s| {
                var dir = std.fs.cwd().openDir(s, .{ .iterate = true }) catch |err| switch (err) {
                    error.NotDir => break :dir_ev, // not a directory, so we can break out of the directory sub-routine
                    else => return err,
                };
                defer dir.close();

                var dir_node = ResourceNode.init(self.allocator, .{
                    .directory = try uri.clone(self.allocator),
                });

                const tmp_path = try std.fmt.allocPrintZ(self.allocator, "/project/{s}", .{uri.path()}); // TODO: remove me
                defer self.allocator.free(tmp_path);
                const gop = try self.resource_tree.getOrPut(tmp_path);
                if (gop.found_existing) {
                    dir_node.deinit(false);
                } else {
                    gop.value.* = dir_node;
                    self.on_register.fire(.{gop.value});
                }

                var dir_iter = dir.iterate();
                while (try dir_iter.next()) |next| {
                    switch (next.kind) {
                        .file, .directory => {
                            const slice = try std.fs.path.join(allocator, &[_][]const u8{ s, next.name });
                            defer allocator.free(slice);
                            try self.onWatchEvent(switch (event) {
                                .add => .{ .add = slice },
                                .remove => .{ .remove = slice },
                                .modify => .{ .modify = slice },
                                .rename_old => .{ .rename_old = slice },
                                .rename_new => .{ .rename_new = slice },
                            });
                        },
                        else => {},
                    }
                }
            },
            .remove, .rename_old => {
                // if resource doesn't exist or isn't a directory, break out of the directory event sub-routine
                const res = (try findResourceNodeByUri(&uri)) orelse break :dir_ev;
                if (res.node != .directory) {
                    break :dir_ev;
                }

                var parent_uri = (try uri.parentUri(self.allocator)) orelse try Uri.parse(self.allocator, "project://");
                defer parent_uri.deinit(self.allocator);
                var parent_res = (try findResourceNodeByUri(&parent_uri)).?;

                var dir_iter = res.children.iterator();

                while (dir_iter.next()) |next| {
                    // TODO: no need to dupe if events become []const u8
                    const slice = try allocator.dupe(u8, try next.value_ptr.node.path());
                    defer allocator.free(slice);
                    try self.onWatchEvent(switch (event) {
                        .add => .{ .add = slice },
                        .remove => .{ .remove = slice },
                        .modify => .{ .modify = slice },
                        .rename_old => .{ .rename_old = slice },
                        .rename_new => .{ .rename_new = slice },
                    });
                }

                std.debug.assert(res.children.count() == 0);
                var res_entry = parent_res.children.fetchOrderedRemoveAdapted(
                    std.fs.path.basename(uri.path()),
                    collections.ArrayHashMapStringAdaptedContext,
                ).?;
                res_entry.value.deinit(true);
                self.allocator.free(res_entry.key);
            },
            .modify => {
                const res = (try findResourceNodeByUri(&uri)) orelse break :dir_ev;
                if (res.node != .directory) {
                    break :dir_ev;
                }
            },
        }

        return;
    }

    switch (event) {
        .add, .rename_new => |p| {
            const path = utils.normalizePathSep(p);
            const baseext = utils.baseExtensionSplit(path);
            if (std.mem.eql(u8, baseext.ext, yume_meta_extension_name)) { // seen new meta
                const uri = try std.fmt.allocPrint(self.allocator, "project://{s}", .{baseext.base});
                defer self.allocator.free(uri);
                if (resourceExistsByUri(uri)) {
                    const res_id = try getResourceId(uri);
                    try syncMeta(res_id, .disk);
                } else if (try utils.pathExists(baseext.base)) {
                    // if resource path exists we attempt to register it
                    _ = try registerFromMeta(.{ .path = baseext.base, .update_uuid_if_exists = true });
                } else {
                    // orphan meta files aren't allowed
                    log.err("Seen a meta file \"{s}\" without the actual resource, removing the meta file.", .{path});
                    try std.fs.cwd().deleteFile(path);
                }
            } else { // seen new resource file
                const maybe_meta = try std.fmt.allocPrint(allocator, "{s}{s}", .{ path, yume_meta_extension_name });
                if (try utils.pathExists(maybe_meta)) {
                    _ = try registerFromMeta(.{ .path = path, .update_uuid_if_exists = true });
                } else {
                    _ = try register(.{
                        .urn = &Uuid.new().urn(),
                        .path = path,
                    });
                }
            }
        },
        .remove, .rename_old => |p| {
            const path = utils.normalizePathSep(p);
            const baseext = utils.baseExtensionSplit(path);
            if (std.mem.eql(u8, baseext.ext, yume_meta_extension_name)) { // removing a meta
                const uri = try std.fmt.allocPrint(self.allocator, "project://{s}", .{baseext.base});
                defer self.allocator.free(uri);
                if (resourceExistsByUri(uri)) {
                    // if the resource already exists, recreate the meta from memory
                    const res_id = try getResourceId(uri);
                    var res = try getResource(self.allocator, res_id);
                    defer res.?.deinit(self.allocator);
                    try res.?.save(self.allocator, true);
                } else if (try utils.pathExists(baseext.base)) {
                    // if a resource file for the removed meta exists, but not registered, register it without meta
                    _ = try register(.{ .urn = &Uuid.new().urn(), .path = baseext.base });
                } else if (try findResourceNode(baseext.base)) |res| {
                    switch (res.node) {
                        .resource => |id| try unregister(id),
                        else => {},
                    }
                } else {
                    // do nothing if removed meta file has no resource associated with it
                }
            } else { // removing a resource
                const maybe_meta = try std.fmt.allocPrint(allocator, "{s}{s}", .{ path, yume_meta_extension_name });
                const uri = try std.fmt.allocPrint(self.allocator, "project://{s}", .{path});
                defer self.allocator.free(uri);
                const res_id = try getResourceId(uri);
                try unregister(res_id);
                if (try utils.pathExists(maybe_meta)) {
                    try std.fs.cwd().deleteFile(maybe_meta);
                }
            }
        },
        .modify => |p| {
            const path = utils.normalizePathSep(p);
            const baseext = utils.baseExtensionSplit(path);
            if (std.mem.eql(u8, baseext.ext, yume_meta_extension_name)) { // modifying a meta file
                const uri = try std.fmt.allocPrint(self.allocator, "project://{s}", .{baseext.base});
                defer self.allocator.free(uri);
                if (resourceExistsByUri(uri)) {
                    const res_id = try getResourceId(uri);
                    try syncMeta(res_id, .disk);
                } else if (try utils.pathExists(baseext.base)) {
                    // if resource path exists we attempt to register it
                    _ = try registerFromMeta(.{ .path = baseext.base, .update_uuid_if_exists = true });
                } else {
                    // orphan meta files aren't allowed
                    log.err("Seen a meta file \"{s}\" without the actual resource, removing the meta file.", .{path});
                    try std.fs.cwd().deleteFile(path);
                }
            } else { // modifying a resource
                const uri = try std.fmt.allocPrint(self.allocator, "project://{s}", .{path});
                defer self.allocator.free(uri);
                if (resourceExistsByUri(uri)) {
                    const res_id = try getResourceId(uri);
                    const ty = try getResourceType(res_id);
                    const handle = assets.AssetHandle{ .uuid = res_id, .type = ty.toAssetType() };
                    try assets.Assets.reload(handle, .{});
                }
            }
        },
    }
}

fn syncMeta(id: Uuid, bias: enum { memory, disk }) !void {
    const self = instance();
    var buf: [1024]u8 = undefined;

    var in_mem = (try getResource(self.allocator, id)).?;

    const meta_path = try in_mem.bufMetaPath(&buf);

    const on_disk = try Resource.load(self.allocator, meta_path);

    const uri: *const Uri = &in_mem.uri;

    var target = if (bias == .memory) in_mem else on_disk;
    errdefer target.deinit(self.allocator);
    var other = if (bias == .memory) on_disk else in_mem;
    defer other.deinit(self.allocator);

    if (!target.eql(&other)) {
        const node = try findResourceNodeByUri(uri) orelse return error.InvalidSyncMetaOperation;
        if (!target.id.eql(in_mem.id)) {
            const old_id = in_mem.id;
            if (try self.resources_index.fetchPut(try self.allocator.dupe(u8, uri.span()), target.id)) |old| {
                self.allocator.free(old.key);
            } else log.err(
                "Invalid sync operation, Resources might be partially broken, old_id: {s}, new_id: {s}, uri: {s}",
                .{ old_id.urn(), target.id.urn(), uri.span() },
            );
            if (self.resources.fetchRemove(id)) |old| {
                var val = old.value;
                val.deinit(self.allocator);
            } else log.err(
                "Invalid sync operation, Resources might be partially broken, old_id: {s}, new_id: {s}, uri: {s}",
                .{ old_id.urn(), target.id.urn(), uri.span() },
            );

            try self.resources.put(target.id, target);

            node.node.resource = target.id;
        } else if (self.resources.getPtr(id)) |res| {
            res.deinit(self.allocator);
            res.* = target;
        } else return error.InvalidSyncMetaOperation;
    } else {
        target.deinit(self.allocator);
    }
}

pub const Uri = extern struct {
    buf: [*:0]u8,
    len: usize,
    protocol_len: usize,

    pub fn parse(allocator: std.mem.Allocator, slice: []const u8) !Uri {
        const owned = try allocator.dupeZ(u8, slice);
        errdefer allocator.free(owned);
        return parseOwnedSlice(owned);
    }

    pub fn parseOwnedSlice(slice: [:0]u8) !Uri {
        var protocol_len: usize = 0;
        for (0..slice.len) |i| {
            if (slice[i] == ':') {
                if (slice.len > i + 2 and slice[i + 1] == '/' and slice[i + 2] == '/') {
                    protocol_len = i;
                    break;
                }
            }
        }

        if (protocol_len == 0) {
            log.err("Invalid Uri: {s}", .{slice});
            return error.InvalidUri;
        }

        return fromOwnedSliceWithProtocolLen(slice, protocol_len);
    }

    pub fn initWithProtocolLen(allocator: std.mem.Allocator, slice: []const u8, protocol_len: usize) !Uri {
        return fromOwnedSliceWithProtocolLen(try allocator.dupeZ(u8, slice), protocol_len);
    }

    pub inline fn fromOwnedSliceWithProtocolLen(slice: [:0]u8, protocol_len: usize) Uri {
        return .{
            .buf = utils.normalizePathSepZ(slice.ptr),
            .len = slice.len,
            .protocol_len = protocol_len,
        };
    }

    // based on std.fs.path.joinSepMaybeZ
    pub fn join(uri: *const Uri, allocator: std.mem.Allocator, paths: []const []const u8) !Uri {
        std.log.debug("joining {s} with {s}", .{ uri, paths[0] });
        if (paths.len == 0) return uri.clone(allocator);

        // Find first non-empty path index.
        const first_path_index = blk: {
            for (paths, 0..) |p, index| {
                if (p.len == 0) continue else break :blk index;
            }

            // All paths provided were empty, so return early.
            return uri.clone(allocator);
        };

        // Calculate length needed for resulting joined path buffer.
        const total_len = blk: {
            var sum: usize = paths[first_path_index].len;
            var prev_path = paths[first_path_index];
            std.debug.assert(prev_path.len > 0);
            var i: usize = first_path_index + 1;
            while (i < paths.len) : (i += 1) {
                const this_path = paths[i];
                if (this_path.len == 0) continue;
                const prev_sep = std.fs.path.isSep(prev_path[prev_path.len - 1]);
                const this_sep = std.fs.path.isSep(this_path[0]);
                sum += @intFromBool(!prev_sep and !this_sep);
                sum += if (prev_sep and this_sep) this_path.len - 1 else this_path.len;
                prev_path = this_path;
            }

            sum += 1;
            break :blk sum;
        };

        const base_uri = uri.span();
        var base_len: usize = base_uri.len;
        if (base_uri[base_uri.len - 1] != '/') {
            base_len += 1;
        }
        const buf = try allocator.alloc(u8, total_len + base_len);
        errdefer allocator.free(buf);
        @memcpy(buf[0..base_uri.len], base_uri);
        if (base_len > base_uri.len) { // needs seperator?
            buf[base_uri.len] = '/';
        }
        @memcpy(buf[base_len .. base_len + paths[first_path_index].len], paths[first_path_index]);
        var buf_index: usize = base_len + paths[first_path_index].len;
        var prev_path = paths[first_path_index];
        std.debug.assert(prev_path.len > 0);
        var i: usize = first_path_index + 1;
        while (i < paths.len) : (i += 1) {
            const this_path = paths[i];
            if (this_path.len == 0) continue;
            const prev_sep = std.fs.path.isSep(prev_path[prev_path.len - 1]);
            const this_sep = std.fs.path.isSep(this_path[0]);
            if (!prev_sep and !this_sep) {
                buf[buf_index] = '/';
                buf_index += 1;
            }
            const adjusted_path = if (prev_sep and this_sep) this_path[1..] else this_path;
            @memcpy(buf[buf_index..][0..adjusted_path.len], adjusted_path);
            buf_index += adjusted_path.len;
            prev_path = this_path;
        }

        buf[buf.len - 1] = 0;

        // No need for shrink since buf is exactly the correct size.
        return fromOwnedSliceWithProtocolLen(buf[0 .. buf.len - 1 :0], uri.protocol_len);
    }

    pub fn deinit(uri: *Uri, allocator: std.mem.Allocator) void {
        allocator.free(uri.buf[0..uri.len :0]);
    }

    // keeps the protocol, updates the remainder of the Uri
    pub fn setPath(uri: *Uri, allocator: std.mem.Allocator, path_: []const u8) !void {
        const len_of_prot_uri = uri.protocol_len + "://".len;
        const new_size = path_.len + len_of_prot_uri;
        const new_buf = try allocator.realloc(utils.absorbSentinel(uri.buf[0..uri.len :0]), new_size + 1);
        @memcpy(new_buf[len_of_prot_uri..new_size], path_);
        uri.buf = @ptrCast(new_buf.ptr);
        uri.buf[new_size] = 0;
        uri.len = new_size;
    }

    pub fn clone(uri: *const Uri, allocator: std.mem.Allocator) !Uri {
        return initWithProtocolLen(allocator, uri.span(), uri.protocol_len);
    }

    pub inline fn span(uri: *const Uri) []const u8 {
        return uri.buf[0..uri.len];
    }

    pub inline fn spanZ(uri: *const Uri) [:0]const u8 {
        return uri.buf[0..uri.len :0];
    }

    pub inline fn path(uri: *const Uri) []const u8 {
        return uri.buf[uri.protocol_len + "://".len .. uri.len];
    }

    pub inline fn pathZ(uri: *const Uri) [:0]const u8 {
        return uri.buf[uri.protocol_len + "://".len .. uri.len :0];
    }

    pub inline fn protocol(uri: *const Uri) []const u8 {
        return uri.buf[0..uri.protocol_len];
    }

    // is protocol `project://`?
    pub inline fn isProject(uri: *const Uri) bool {
        return std.mem.eql(u8, uri.protocol(), "project");
    }

    // shortthand for checking if URI is exactly `:://`
    pub inline fn isRoot(uri: *const Uri) bool {
        return std.mem.eql(u8, uri.span(), ":://");
    }

    // shortthand for checking if URI is starting with `:://`
    pub inline fn isInRoot(uri: *const Uri) bool {
        return std.mem.eql(u8, uri.protocol(), ":");
    }

    // includes the `://` portion as well
    pub inline fn protocolWithSeperator(uri: *const Uri) []const u8 {
        return uri.buf[0 .. uri.protocol_len + "://".len];
    }

    // if uri is at the root, e.g. `project://` it will return null
    pub fn parent(uri: *const Uri) ?[]const u8 {
        return if (uri.len == uri.protocol_len + "://".len)
            null
        else if (std.fs.path.dirname(uri.path())) |dirname|
            uri.buf[0 .. uri.protocol_len + "://".len + dirname.len]
        else
            null;
    }

    pub fn parentUri(uri: *const Uri, allocator: std.mem.Allocator) !?Uri {
        if (uri.parent()) |p| {
            return try initWithProtocolLen(allocator, p, uri.protocol_len);
        } else {
            return null;
        }
    }

    pub fn parentUriOr(uri: *const Uri, or_kind: enum { root, protocol_uri }, allocator: std.mem.Allocator) !Uri {
        if (uri.parent()) |p| {
            return try initWithProtocolLen(allocator, p, uri.protocol_len);
        } else {
            return switch (or_kind) {
                .root => initWithProtocolLen(allocator, ":://", 1),
                .protocol_uri => initWithProtocolLen(allocator, uri.protocolWithSeperator(), uri.protocol_len),
            };
        }
    }

    pub fn bufFullpath(uri: *const Uri, buf: []u8) ![:0]const u8 {
        if (std.mem.eql(u8, uri.protocol(), "project")) {
            const slice = try std.fs.cwd().realpath(uri.path(), buf);
            if (buf.len <= slice.len) return error.NoSpaceLeft;
            buf[slice.len] = 0;
            return utils.normalizePathSepZ(@ptrCast(slice.ptr))[0..slice.len :0];
        } else {
            var editor_root_buf: [std.fs.max_path_bytes]u8 = undefined;
            const editor_root = try Editor.bufRootDir(&editor_root_buf);
            return try std.fmt.bufPrintZ(buf, "{s}/resources/{s}/{s}", .{ editor_root, uri.protocol(), uri.path() });
        }
    }

    pub inline fn eql(lhs: *const Uri, rhs: *const Uri) bool {
        return lhs.protocol_len == rhs.protocol_len and
            std.mem.eql(u8, lhs.span(), rhs.span());
    }

    pub fn jsonStringify(uri: *const Uri, jws: anytype) !void {
        return jws.write(uri.span());
    }

    pub fn jsonParse(allocator: std.mem.Allocator, jrs: anytype, _: anytype) !Uri {
        const tk = try jrs.nextAlloc(allocator, .alloc_if_needed);

        switch (tk) {
            inline .string => |s| return parse(allocator, s) catch return error.UnexpectedToken,
            inline .allocated_string => |s| {
                defer allocator.free(s);
                return parse(allocator, s) catch return error.UnexpectedToken;
            },
            else => {
                log.err("{}\n", .{tk});
                return error.UnexpectedToken;
            },
        }
    }

    pub fn format(
        uri: *const Uri,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        return writer.print("{s}", .{uri.span()});
    }

    pub const ComponentIterator = struct {
        pub const Result = struct {
            name: []const u8,
            uri: []const u8,
        };
        buf: [*:0]const u8,
        next_len: usize,
        cursor: usize = 0,
        next_token_type: enum { protocol, segment, last } = .protocol,

        pub fn peek(iter: *const ComponentIterator) ?Result {
            if (iter.next_len == 0) {
                return null;
            }

            const name_slice = iter.buf[iter.cursor .. iter.cursor + iter.next_len];
            const cursor = iter.cursor + iter.next_len;
            return switch (iter.next_token_type) {
                .protocol => Result{
                    .name = name_slice,
                    .uri = iter.buf[0 .. cursor + "://".len],
                },
                .segment => Result{
                    .name = name_slice,
                    .uri = iter.buf[0 .. cursor + "/".len],
                },
                .last => Result{
                    .name = name_slice,
                    .uri = iter.buf[0..cursor],
                },
            };
        }

        pub fn next(iter: *ComponentIterator) ?Result {
            const it = iter.peek() orelse return null;

            iter.cursor = it.uri.len;
            var i: usize = iter.cursor;
            while (true) : (i += 1) {
                if (iter.buf[i] == 0) {
                    iter.next_token_type = .last;
                    break;
                }

                if (iter.buf[i] == '/') {
                    iter.next_token_type = .segment;
                    break;
                }
            }

            iter.next_len = i - iter.cursor;

            return it;
        }
    };

    pub fn componentIterator(
        uri: *const Uri,
    ) ComponentIterator {
        return ComponentIterator{ .buf = uri.buf, .next_len = uri.protocol_len };
    }
};
