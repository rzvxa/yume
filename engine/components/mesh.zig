const c = @import("clibs");
const std = @import("std");
const log = std.log.scoped(.mesh);

const AllocatedBuffer = @import("../VulkanEngine.zig").AllocatedBuffer;
const m3d = @import("../math3d.zig");

const ecs = @import("../ecs.zig");
const GameApp = @import("../GameApp.zig");
const Assets = @import("../assets.zig").Assets;
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
    uuid: Uuid,
    vertices_count: usize,
    vertices: [*c]Vertex,
    bounds: BoundingBox,
    vertex_buffer: AllocatedBuffer = undefined,

    pub fn editorIcon() [*:0]const u8 {
        return "editor://icons/mesh.png";
    }

    pub fn default(ptr: *Mesh, _: ecs.Entity, _: *GameApp, rr: ecs.ResourceResolver) callconv(.C) bool {
        const cube = rr("builtin://cube.obj");
        if (!cube.found) {
            return false;
        }

        ptr.* = (Assets.getOrLoadMesh(cube.uuid) catch return false).*;
        return true;
    }

    pub fn serialize(self: *const @This(), allocator: std.mem.Allocator) !Dynamic {
        return .{ .type = .string, .value = .{ .string = try allocator.dupeZ(u8, &self.uuid.urn()) } };
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, _: std.mem.Allocator) !void {
        const urn = try value.expectString();
        const uuid = try Uuid.fromUrnSlice(std.mem.span(urn));
        self.* = (try Assets.getOrLoadMesh(uuid)).*;
    }
};

pub fn load_from_obj(allocator: std.mem.Allocator, buffer: []const u8) Mesh {
    var obj_mesh = obj_loader.parse(allocator, buffer, ":memory:") catch |err| {
        std.log.err("Failed to load obj file: {s}", .{@errorName(err)});
        unreachable;
    };
    defer obj_mesh.deinit();

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

        // get (len - n)'th element
        fn getFromEnd(self: *@This(), n: usize) Vertex {
            return self.vertices.items[self.vertices.items.len - n];
        }

        fn append(self: *@This(), vert: Vertex) void {
            self.bounds.accumulate(vert.position);
            self.vertices.append(vert) catch @panic("OOM");
        }
    }.builder(allocator);

    for (obj_mesh.objects) |object| {
        var index_count: usize = 0;
        for (object.face_vertices) |face_vx_count| {
            if (face_vx_count < 3) {
                @panic("Face has fewer than 3 vertices. Not a valid polygon.");
            }

            for (0..face_vx_count) |vx_index| {
                const obj_index = object.indices[index_count];
                const pos = obj_mesh.vertices[obj_index.vertex];
                const nml = obj_mesh.normals[obj_index.normal];
                const uvs = obj_mesh.uvs[obj_index.uv];

                const vx = Vertex{
                    .position = Vec3.make(pos[0], pos[1], pos[2]),
                    .normal = Vec3.make(nml[0], nml[1], nml[2]),
                    .color = Vec3.make(nml[0], nml[1], nml[2]),
                    .uv = Vec2.make(uvs[0], 1.0 - uvs[1]),
                };

                // Triangulate the polygon
                if (vx_index > 2) {
                    const v0 = vb.getFromEnd(3);
                    const v1 = vb.getFromEnd(1);
                    vb.append(v0);
                    vb.append(v1);
                }

                vb.append(vx);

                index_count += 1;
            }
        }
    }

    return Mesh{
        .uuid = Uuid.new(),
        .vertices_count = vb.vertices.items.len,
        .vertices = (vb.vertices.toOwnedSlice() catch @panic("Failed to make owned slice")).ptr,
        .bounds = vb.bounds,
    };
}

pub fn load_from_obj2(allocator: std.mem.Allocator, buffer: []const u8) Mesh {
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
        log.debug("Object: {s}\n", .{node.*.*.attrib.*.name.data});
        const mesh = node.*.*.mesh;

        const num_tri_indices = mesh.*.max_face_triangles * 3;
        const tri_indices = allocator.alloc(u32, num_tri_indices) catch @panic("OOM");
        defer allocator.free(tri_indices);
        std.debug.assert(mesh != null);
        log.debug("-> mesh with {} faces\n-> materials {}\n", .{ mesh.*.faces.count, mesh.*.face_groups.count });
        for (mesh.*.faces.data[0..mesh.*.faces.count]) |face| {
            if (face.num_indices < 3) {
                @panic("Face has fewer than 3 vertices. Not a valid polygon.");
            }
            const num_tries = c.ufbx_triangulate_face(tri_indices.ptr, num_tri_indices, mesh, face);

            for (0..num_tries * 3) |vi| {
                const index = tri_indices[vi];
                std.debug.assert(mesh.*.vertex_position.exists);
                const position = Vec3.fromArray(c.ufbx_get_vertex_vec3(&mesh.*.vertex_position, index).unnamed_0.v);
                std.debug.assert(mesh.*.vertex_normal.exists);
                const normal = Vec3.fromArray(c.ufbx_get_vertex_vec3(&mesh.*.vertex_normal, index).unnamed_0.v);
                const tangent = blk: {
                    if (mesh.*.vertex_tangent.exists) {
                        std.debug.assert(mesh.*.vertex_bitangent.exists);
                        const bitangent = Vec3.fromArray(c.ufbx_get_vertex_vec3(&mesh.*.vertex_bitangent, index).unnamed_0.v);
                        const tangent = Vec3.fromArray(c.ufbx_get_vertex_vec3(&mesh.*.vertex_tangent, index).unnamed_0.v);
                        const handedness: f32 = if (normal.cross(tangent).dot(bitangent) < 0.0) -1.0 else 1.0;
                        break :blk tangent.toVec4(handedness);
                    } else {
                        break :blk Vec4.ZERO;
                    }
                };

                const color = if (mesh.*.vertex_color.exists)
                    Vec4.fromArray(c.ufbx_get_vertex_vec4(&mesh.*.vertex_color, index).unnamed_0.v)
                else
                    Vec4.scalar(1);
                const uv = if (mesh.*.vertex_uv.exists)
                    Vec2.fromArray(c.ufbx_get_vertex_vec2(&mesh.*.vertex_uv, index).unnamed_0.v)
                else
                    Vec2.ZERO;

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

    return Mesh{
        .uuid = Uuid.new(),
        .vertices_count = vb.vertices.items.len,
        .vertices = (vb.vertices.toOwnedSlice() catch @panic("Failed to make owned slice")).ptr,
        .bounds = vb.bounds,
    };
}
