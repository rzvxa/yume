const std = @import("std");

const Uuid = @import("yume").Uuid;
const log = std.log.scoped(.AssetsDatabase);

pub const Resource = struct {
    id: Uuid,
    path: []u8,
};

const Self = @This();

var singleton: ?Self = null;

allocator: std.mem.Allocator,

resources: std.AutoHashMap(Uuid, Resource),

resources_index: std.StringHashMap(Uuid),
resources_builtins: std.AutoHashMap(Uuid, Resource),

fn instance() *Self {
    std.debug.assert(singleton != null);
    return &singleton.?;
}

pub fn init(allocator: std.mem.Allocator) !void {
    std.debug.assert(singleton == null);
    singleton = Self{
        .allocator = allocator,
        .resources = std.AutoHashMap(Uuid, Resource).init(allocator),
        .resources_index = std.StringHashMap(Uuid).init(allocator),
        .resources_builtins = std.AutoHashMap(Uuid, Resource).init(allocator),
    };

    {
        try register(.{ .urn = "3e21192b-6c22-4a4f-98ca-a4a43f675986", .path = "materials/default.mat", .category = "builtin" });
        try register(.{ .urn = "e732bb0c-19bb-492b-a79d-24fde85964d2", .path = "materials/none.mat", .category = "builtin" });
        try register(.{ .urn = "ad4bc22b-3765-4a9d-bab7-7984e101428a", .path = "lost_empire-RGBA.png", .category = "builtin" });
        try register(.{ .urn = "ac6b9d14-0a56-458a-a7cc-fd36ede79468", .path = "lost_empire.obj", .category = "builtin" });
        try register(.{ .urn = "acc02aef-7ac0-46e7-b006-378c36ac1b27", .path = "u.obj", .category = "builtin" });
        try register(.{ .urn = "17c0ee4b-8fa0-43a7-a3d8-8bf7b5e73bb9", .path = "u.mtl", .category = "builtin" });
        try register(.{ .urn = "23400ade-52d7-416b-9679-884a49de1722", .path = "cube.obj", .category = "builtin" });
    }

    {
        try registerBuiltinShader("cf64bfc9-703c-43b0-9d01-c8032706872c", "tri_mesh.vert.glsl");
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

        try register(.{ .urn = "72bb403a-8624-4541-bbaa-a85668340db1", .path = "icons/camera.png", .category = "editor" });
        try register(.{ .urn = "1e2e7db3-8b27-45b9-adf1-05e808175043", .path = "icons/mesh.png", .category = "editor" });
        try register(.{ .urn = "849d928a-a459-4df7-97c4-49877fba782c", .path = "icons/material.png", .category = "editor" });

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

pub fn deinit() void {
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
        var it = self.resources_builtins.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.value_ptr.path);
        }
    }
    self.resources_builtins.deinit();
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
    log.err("resource not found {s}\n", .{path});
    return error.ResourceNotFound;
}

pub fn getResourcePath(id: Uuid) ![]const u8 {
    const self = instance();
    if (self.resources_builtins.get(id)) |b| {
        return b.path;
    }

    const res = self.resources.get(id);
    if (res) |r| {
        return r.path;
    } else {
        return error.ResourceNotFound;
    }
}

pub fn readAssetAlloc(allocator: std.mem.Allocator, id: Uuid, max_bytes: usize) ![]u8 {
    log.debug("readAssetAlloc ({s}) :: {s}\n", .{ id.urn(), try getResourcePath(id) });
    var file = std.fs.cwd().openFile(try getResourcePath(id), .{}) catch return error.FailedToOpenResource;
    defer file.close();
    return file.readToEndAlloc(allocator, max_bytes) catch return error.FailedToReadResource;
}

pub fn register(opts: struct {
    urn: []const u8,
    path: []const u8,
    category: []const u8 = "assets",
}) !void {
    const is_builtin = std.mem.eql(u8, opts.category, "builtin") or std.mem.eql(u8, opts.category, "editor");
    var self = instance();
    const id = try Uuid.fromUrnSlice(opts.urn);
    const gameRoot = try gameRootDirectory(self.allocator);
    defer self.allocator.free(gameRoot);

    var storage = if (is_builtin) &self.resources_builtins else &self.resources;
    const path = if (is_builtin)
        try std.fs.path.join(self.allocator, &[_][]const u8{ gameRoot, "assets", opts.category, opts.path })
    else
        try self.allocator.dupe(u8, opts.path);

    try storage.put(id, Resource{ .id = id, .path = path });
    const uri = try std.fmt.allocPrint(self.allocator, "{s}://{s}", .{ opts.category, opts.path });
    try self.resources_index.put(uri, id);
}

fn registerBuiltinShader(urn: []const u8, path: []const u8) !void {
    const self = instance();
    const id = try Uuid.fromUrnSlice(urn);
    const gameRoot = try gameRootDirectory(self.allocator);
    defer self.allocator.free(gameRoot);
    const pathspv = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ path[0 .. path.len - ".glsl".len], "spv" });
    defer self.allocator.free(pathspv);
    try self.resources_builtins.put(id, Resource{
        .id = id,
        .path = try std.fs.path.join(self.allocator, &[_][]const u8{ gameRoot, "shaders", pathspv }),
    });
    const uri = try std.fmt.allocPrint(self.allocator, "builtin://{s}", .{path});
    try self.resources_index.put(uri, id);
}

inline fn gameRootDirectory(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExeDirPath(&buf);
    const dirname = std.fs.path.dirname(exe_path) orelse return error.InvalidPath;
    return allocator.dupe(u8, dirname);
}
