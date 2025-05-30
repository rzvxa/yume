const c = @import("clibs");
const std = @import("std");
const log = std.log.scoped(.mesh);

const AllocatedBuffer = @import("../VulkanEngine.zig").AllocatedBuffer;
const m3d = @import("../math3d.zig");

const ecs = @import("../ecs.zig");
const GameApp = @import("../GameApp.zig");
const assets = @import("../assets.zig");
const Assets = assets.Assets;
const Dynamic = @import("../serialization/dynamic.zig").Dynamic;

const Uuid = @import("../uuid.zig").Uuid;
const obj_loader = @import("../obj_loader.zig");

const Vec2 = m3d.Vec2;
const Vec3 = m3d.Vec3;
const Vec4 = m3d.Vec4;
const Mat4 = m3d.Mat4;

pub const VertexInputDescription = struct {
    bindings: []const c.VkVertexInputBindingDescription,
    attributes: []const c.VkVertexInputAttributeDescription,

    flags: c.VkPipelineVertexInputStateCreateFlags = 0,
};

pub const Vertex = extern struct {
    position: Vec3,
    normal: Vec3,
    tangent: Vec4,
    color: Vec4,
    uv: Vec2,

    pub const vertex_input_description = VertexInputDescription{
        .bindings = &.{
            std.mem.zeroInit(c.VkVertexInputBindingDescription, .{
                .binding = 0,
                .stride = @sizeOf(Vertex),
                .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
            }),
        },
        .attributes = &.{
            std.mem.zeroInit(c.VkVertexInputAttributeDescription, .{
                .location = 0,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "position"),
            }),
            std.mem.zeroInit(c.VkVertexInputAttributeDescription, .{
                .location = 1,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "normal"),
            }),
            std.mem.zeroInit(c.VkVertexInputAttributeDescription, .{
                .location = 2,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(Vertex, "tangent"),
            }),
            std.mem.zeroInit(c.VkVertexInputAttributeDescription, .{
                .location = 3,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            }),
            std.mem.zeroInit(c.VkVertexInputAttributeDescription, .{
                .location = 4,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "uv"),
            }),
        },
    };
};

pub const BoundingBox = extern struct {
    const Self = @This();
    mins: Vec3,
    maxs: Vec3,

    pub fn accumulate(self: *Self, pos: Vec3) void {
        self.mins.x = @min(self.mins.x, pos.x);
        self.mins.y = @min(self.mins.y, pos.y);
        self.mins.z = @min(self.mins.z, pos.z);

        self.maxs.x = @max(self.maxs.x, pos.x);
        self.maxs.y = @max(self.maxs.y, pos.y);
        self.maxs.z = @max(self.maxs.z, pos.z);
    }

    pub fn accumulateBB(self: *Self, other: Self) void {
        self.mins.x = @min(self.mins.x, other.mins.x);
        self.mins.y = @min(self.mins.y, other.mins.y);
        self.mins.z = @min(self.mins.z, other.mins.z);

        self.maxs.x = @max(self.maxs.x, other.maxs.x);
        self.maxs.y = @max(self.maxs.y, other.maxs.y);
        self.maxs.z = @max(self.maxs.z, other.maxs.z);
    }

    pub fn translate(self: Self, mat: Mat4) Self {
        return .{
            .mins = mat.mulVec3(self.mins),
            .maxs = mat.mulVec3(self.maxs),
        };
    }
};

pub const Mesh = extern struct {
    handle: assets.MeshHandle,
    vertices_count: usize,
    vertices: [*c]Vertex,
    bounds: BoundingBox,
    vertex_buffer: AllocatedBuffer = undefined,

    pub fn editorIcon() [*:0]const u8 {
        return "editor://icons/mesh.png";
    }

    pub fn deinit(self: *Mesh) void {
        Assets.release(self.handle) catch {};
    }

    pub fn default(ptr: *Mesh, _: ecs.Entity, _: *GameApp, rr: ecs.ResourceResolver) callconv(.C) bool {
        const handle = rr("builtin://cube.obj").toAssetHandle() catch |err| {
            log.err("encountered error on creating the default mesh, {}", .{err});
            return false;
        };

        ptr.* = (Assets.get(handle.unbox(.mesh)) catch return false).*;
        return true;
    }

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        return .{ .type = .string, .value = .{ .string = try allocator.dupeZ(u8, &self.handle.uuid.urn()) } };
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, _: std.mem.Allocator) !void {
        const urn = try value.expectString();
        const uuid = try Uuid.fromUrnSlice(std.mem.span(urn));
        self.* = (try Assets.get(assets.MeshHandle{ .uuid = uuid })).*;
    }
};

pub fn load_from_obj(
    allocator: std.mem.Allocator,
    handle: assets.MeshHandle,
    buffer: []const u8,
) Mesh {
    const smooth = false;
    var computedNormalsUsed: bool = false;
    var err: c.ufbx_error = std.mem.zeroes(c.ufbx_error);
    const scene = c.ufbx_load_memory(buffer.ptr, buffer.len, &.{}, &err);
    if (scene == null) {
        std.log.err("Failed to load obj: {s}", .{err.description.data});
        unreachable;
    }
    defer c.ufbx_free_scene(scene);

    var vb = struct {
        vertices: std.ArrayList(Vertex),
        bounds: BoundingBox,

        fn builder(a: std.mem.Allocator) @This() {
            return .{
                .vertices = std.ArrayList(Vertex).init(a),
                .bounds = .{
                    .mins = Vec3.scalar(std.math.floatMax(f32)),
                    .maxs = Vec3.scalar(std.math.floatMin(f32)),
                },
            };
        }

        fn append(self: *@This(), vert: Vertex) void {
            self.bounds.accumulate(vert.position);
            self.vertices.append(vert) catch @panic("OOM");
        }
    }.builder(allocator);

    log.debug("{any}", .{scene});
    std.debug.assert(scene.*.root_node.*.children.count == 1);
    for (scene.*.root_node.*.children.data[0..scene.*.root_node.*.children.count]) |*node| {
        log.debug("Object: {s}", .{node.*.*.attrib.*.name.data});
        const mesh = node.*.*.mesh;
        std.debug.assert(mesh != null);
        log.debug("-> mesh with {} faces\n\t\t-> materials {}", .{ mesh.*.faces.count, mesh.*.face_groups.count });

        const num_tri_indices = mesh.*.max_face_triangles * 3;
        const tri_indices = allocator.alloc(u32, num_tri_indices) catch @panic("OOM");
        defer allocator.free(tri_indices);
        // Loop over each face.
        for (mesh.*.faces.data[0..mesh.*.faces.count]) |face| {
            if (face.num_indices < 3) {
                @panic("Face has fewer than 3 vertices. Not a valid polygon.");
            }
            const num_triangles = c.ufbx_triangulate_face(tri_indices.ptr, num_tri_indices, mesh, face);
            // Process each triangle produced.
            for (0..num_triangles) |t| {
                const i_0 = tri_indices[t * 3 + 0];
                const i_1 = tri_indices[t * 3 + 1];
                const i_2 = tri_indices[t * 3 + 2];

                const pos0 = Vec3.fromArray(c.ufbx_get_vertex_vec3(&mesh.*.vertex_position, i_0).unnamed_0.v);
                const pos1 = Vec3.fromArray(c.ufbx_get_vertex_vec3(&mesh.*.vertex_position, i_1).unnamed_0.v);
                const pos2 = Vec3.fromArray(c.ufbx_get_vertex_vec3(&mesh.*.vertex_position, i_2).unnamed_0.v);

                var computed_normal: Vec3 = Vec3.scalar(0);
                if (!mesh.*.vertex_normal.exists) {
                    computedNormalsUsed = true;
                    // Compute flat (face) normal.
                    const edge1 = pos1.sub(pos0);
                    const edge2 = pos2.sub(pos0);
                    computed_normal = edge1.cross(edge2).normalized();
                }

                // Process each vertex of this triangle.
                for (0..3) |j| {
                    const index = tri_indices[t * 3 + j];
                    const position = switch (j) {
                        0 => pos0,
                        1 => pos1,
                        2 => pos2,
                        else => Vec3.scalar(0),
                    };

                    var normal: Vec3 = undefined;
                    if (mesh.*.vertex_normal.exists) {
                        normal = Vec3.fromArray(c.ufbx_get_vertex_vec3(&mesh.*.vertex_normal, index).unnamed_0.v);
                    } else {
                        normal = computed_normal;
                    }

                    const tangent = blk: {
                        if (mesh.*.vertex_tangent.exists) {
                            std.debug.assert(mesh.*.vertex_bitangent.exists);
                            const bitangent = Vec3.fromArray(c.ufbx_get_vertex_vec3(&mesh.*.vertex_bitangent, index).unnamed_0.v);
                            const tng = Vec3.fromArray(c.ufbx_get_vertex_vec3(&mesh.*.vertex_tangent, index).unnamed_0.v);
                            const handedness: f32 = if (normal.cross(tng).dot(bitangent) < 0.0) -1.0 else 1.0;
                            break :blk tng.toVec4(handedness);
                        } else {
                            break :blk Vec4.scalar(0);
                        }
                    };

                    const color = if (mesh.*.vertex_color.exists)
                        Vec4.fromArray(c.ufbx_get_vertex_vec4(&mesh.*.vertex_color, index).unnamed_0.v)
                    else
                        Vec4.scalar(1);
                    const uv = if (mesh.*.vertex_uv.exists)
                        Vec2.fromArray(c.ufbx_get_vertex_vec2(&mesh.*.vertex_uv, index).unnamed_0.v)
                    else
                        Vec2.scalar(0);

                    vb.append(.{
                        .position = position,
                        .normal = normal,
                        .tangent = tangent,
                        .color = color,
                        .uv = uv,
                    });
                }
            }
        }
    }

    // Post-process vertex normals for smoothing if desired and if normals were computed.
    if (smooth and computedNormalsUsed) {
        // Use an epsilon for comparing vertex positions.
        const eps: f32 = 1e-4;
        // Iterate over each vertex and average normals of vertices with matching positions.
        // This is an O(n^2) pass; for large meshes you might want to use spatial hashing.
        for (vb.vertices.items, 0..) |*v, i| {
            var sum: Vec3 = v.normal;
            var count: usize = 1;
            for (vb.vertices.items, 0..) |other, j| {
                if (i != j) {
                    if (@abs(v.position.x - other.position.x) < eps and
                        @abs(v.position.y - other.position.y) < eps and
                        @abs(v.position.z - other.position.z) < eps)
                    {
                        sum = sum.add(other.normal);
                        count += 1;
                    }
                }
            }
            v.normal = (sum.divf(@floatFromInt(count))).normalized();
        }
    }

    return Mesh{
        .handle = handle,
        .vertices_count = vb.vertices.items.len,
        .vertices = (vb.vertices.toOwnedSlice() catch @panic("Failed to make owned slice")).ptr,
        .bounds = vb.bounds,
    };
}
