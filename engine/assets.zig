const std = @import("std");

const Uuid = @import("uuid.zig").Uuid;
const Texture = @import("textures.zig").Texture;

const AssetsDatabase = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    textures: std.AutoHashMap(TextureAssetHandle, Texture),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .textures = std.StringHashMap(Texture).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.textures.deinit();
    }

    pub fn loadTexture(self: *Self, uri: []const u8) TextureAssetHandle {
        const parsed = std.Uri.parse(uri);
        if (std.mem.eql(u8, parsed.scheme, "builtin")) {}
    }
};

const TextureAssetHandle = struct {
    uuid: Uuid,
};

fn resolveUri(allocator: std.mem.Allocator, uri: std.Uri) []const u8 {
    const builtin_leading_path: []const u8 = "";
    if (std.mem.eql(u8, uri.scheme, "builtin")) {
        return std.fmt.allocPrint(allocator, "{s}/{s}", builtin_leading_path, uri.path.raw);
    }

    @panic("Not Implemented!" ++ uri.raw);
}
