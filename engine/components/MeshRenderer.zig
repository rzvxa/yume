const std = @import("std");
const Object = @import("../scene.zig").Object;
const Component = @import("../scene.zig").Component;
const ComponentDefinition = @import("../scene.zig").ComponentDefinition;
const AssetDatabase = @import("../assets.zig").AssetsDatabase;
const Mesh = @import("../mesh.zig").Mesh;
const BoundingBox = @import("../mesh.zig").BoundingBox;
const Material = @import("../VulkanEngine.zig").Material;
const Uuid = @import("../uuid.zig").Uuid;

const typeId = @import("../utils.zig").typeId;

const Self = @This();
object: *Object,
mesh: *Mesh,
material: *Material,

pub fn init(object: *Object, opts: struct { mesh: *Mesh, material: *Material }) Self {
    return .{
        .object = object,
        .mesh = opts.mesh,
        .material = opts.material,
    };
}

pub fn bounds(self: *const @This()) BoundingBox {
    return self.mesh.bounds;
}

pub fn worldBounds(self: *const @This()) BoundingBox {
    return self.bounds().translate(self.object.transform);
}

fn default(allocator: std.mem.Allocator, obj: *Object) !Component {
    const self = try allocator.create(Self);
    self.* = init(obj, .{
        .mesh = try AssetDatabase.getOrLoadMesh(try Uuid.fromUrnSlice("23400ade-52d7-416b-9679-884a49de1722")),
        .material = try AssetDatabase.getOrLoadMaterial(try Uuid.fromUrnSlice("e732bb0c-19bb-492b-a79d-24fde85964d2")),
    });
    return self.asComponent();
}

fn destroy(allocator: std.mem.Allocator, ptr: *Self) void {
    allocator.destroy(ptr);
}

fn fromJson(s: []const u8, ptr: *Self) !void {
    _ = s;
    _ = ptr;
}

fn toJson(self: *Self) []u8 {
    _ = self;
    return &[_]u8{};
}

pub fn asComponent(self: *@This()) Component {
    return .{
        .type_id = typeId(@This()),
        .name = "Mesh Renderer",
        .ptr = self,
        .bounds = struct {
            fn bounds(ptr: *anyopaque) BoundingBox {
                return Self.bounds(@ptrCast(@alignCast(ptr)));
            }
        }.bounds,
    };
}

pub fn definition() ComponentDefinition {
    return .{
        .type_id = typeId(Self),
        .name = "Mesh Renderer",
        .create_default = @ptrCast(&Self.default),
        .destroy = @ptrCast(&Self.destroy),
        .fromJson = @ptrCast(&Self.fromJson),
        .toJson = @ptrCast(&Self.toJson),
    };
}
