const c = @import("clibs");

const std = @import("std");

const Uuid = @import("uuid.zig");
const texs = @import("textures.zig");
const Texture = texs.Texture;

const Mesh = @import("mesh.zig").Mesh;
const load_from_obj = @import("mesh.zig").load_from_obj;

const Engine = @import("VulkanEngine.zig");

const check_vk = @import("vulkan_init.zig").check_vk;

pub const AssetsDatabase = struct {
    const Self = @This();

    var instance: AssetsDatabase = undefined;

    allocator: std.mem.Allocator,
    engine: *Engine,
    loaded_paths: std.StringHashMap(AssetHandle),
    loaded_assets: std.AutoHashMap(AssetHandle, LoadedAsset),

    pub fn init(allocator: std.mem.Allocator, engine: *Engine) void {
        instance = .{
            .allocator = allocator,
            .engine = engine,
            .loaded_paths = std.StringHashMap(AssetHandle).init(allocator),
            .loaded_assets = std.AutoHashMap(AssetHandle, LoadedAsset).init(allocator),
        };
    }

    pub fn deinit() void {
        {
            var iter = instance.loaded_assets.valueIterator();
            while (iter.next()) |it| {
                it.unload();
            }
        }
        instance.loaded_assets.deinit();
        instance.loaded_paths.deinit();
    }

    pub fn getTexture(hndl: TextureAssetHandle) !*Texture {
        const asset = try getLoadedAsset(hndl.toAssetHandle(), .texture);
        return asset.data.texture;
    }

    pub fn loadTexture(uri: []const u8) !TextureAssetHandle {
        if (instance.loaded_paths.get(uri)) |cached| {
            return TextureAssetHandle.fromAssetHandleUnsafe(cached);
        }
        const handle = TextureAssetHandle{ .uuid = Uuid.new() };
        const filepath = resolveUri(uri);

        const image = try texs.load_image_from_file(instance.engine, filepath);

        const image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .image = image.image,
            .format = c.VK_FORMAT_R8G8B8A8_UNORM,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        });

        var texture = try instance.allocator.create(Texture);
        texture.* = Texture{
            .image = image,
            .image_view = null,
        };

        check_vk(c.vkCreateImageView(instance.engine.device, &image_view_ci, Engine.vk_alloc_cbs, &texture.image_view)) catch @panic("Failed to create image view");

        const loaded = LoadedAsset{ .data = .{ .texture = texture } };
        instance.loaded_assets.put(handle.toAssetHandle(), loaded) catch @panic("Out of memory");
        return handle;
    }

    pub fn getOrLoadMesh(uri: []const u8) !*Mesh {
        const hndl = try loadMesh(uri);
        return getMesh(hndl);
    }

    pub fn getMesh(hndl: MeshAssetHandle) !*Mesh {
        const asset = try getLoadedAsset(hndl.toAssetHandle(), .mesh);
        return asset.data.mesh;
    }

    pub fn loadMesh(uri: []const u8) !MeshAssetHandle {
        if (instance.loaded_paths.get(uri)) |cached| {
            return MeshAssetHandle.fromAssetHandleUnsafe(cached);
        }
        const handle = MeshAssetHandle{ .uuid = Uuid.new() };
        const filepath = resolveUri(uri);

        const mesh = try instance.allocator.create(Mesh);
        mesh.* = load_from_obj(instance.allocator, filepath);
        instance.engine.uploadMesh(mesh);

        const loaded = LoadedAsset{ .data = .{ .mesh = mesh } };
        instance.loaded_assets.put(handle.toAssetHandle(), loaded) catch @panic("Out of memory");
        return handle;
    }

    pub fn getLoadedAsset(hndl: AssetHandle, ty: AssetType) !LoadedAsset {
        const it = instance.loaded_assets.get(hndl) orelse return error.AssetNotLoaded;
        if (it.assetType() != ty) return error.InvalidType;
        return it;
    }
};

const AssetType = enum {
    texture,
    mesh,
};

pub const AssetHandle = struct {
    uuid: Uuid,
};

pub const TextureAssetHandle = struct {
    uuid: Uuid,

    pub inline fn toAssetHandle(hndl: @This()) AssetHandle {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetHandleUnsafe(hndl: AssetHandle) @This() {
        return .{ .uuid = hndl.uuid };
    }
};

pub const MeshAssetHandle = struct {
    uuid: Uuid,

    pub inline fn toAssetHandle(hndl: @This()) AssetHandle {
        return .{ .uuid = hndl.uuid };
    }

    inline fn fromAssetHandleUnsafe(hndl: AssetHandle) @This() {
        return .{ .uuid = hndl.uuid };
    }
};

const LoadedAsset = struct {
    const Self = @This();
    data: union(AssetType) {
        texture: *Texture,
        mesh: *Mesh,
    },

    pub fn assetType(self: *const Self) AssetType {
        return @enumFromInt(@intFromEnum(self.data));
    }

    fn unload(self: *Self) void {
        switch (self.data) {
            .texture => {
                const it = self.data.texture;
                var img_del = Engine.VmaImageDeleter{ .image = it.image };
                img_del.delete(AssetsDatabase.instance.engine);
                var view_del = Engine.VulkanDeleter.make(
                    it.image_view,
                    c.vkDestroyImageView,
                );
                view_del.delete(AssetsDatabase.instance.engine);
                AssetsDatabase.instance.allocator.destroy(it);
            },
            .mesh => {
                const it = self.data.mesh;
                AssetsDatabase.instance.allocator.free(it.vertices);
                AssetsDatabase.instance.allocator.destroy(it);
            },
        }
    }
};

fn resolveUri(uri: []const u8) []const u8 {
    const BUILTIN_SCHEMA = "builtin://";
    if (uri.len > BUILTIN_SCHEMA.len and std.mem.eql(u8, uri[0..BUILTIN_SCHEMA.len], BUILTIN_SCHEMA)) {
        return uri[BUILTIN_SCHEMA.len..];
    } else {
        @panic("Not Implemented");
    }
}
