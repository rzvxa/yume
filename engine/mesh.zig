const c = @import("clibs");

const std = @import("std");
const AllocatedBuffer = @import("VulkanEngine.zig").AllocatedBuffer;
const m3d = @import("math3d.zig");

const Vec2 = m3d.Vec2;
const Vec3 = m3d.Vec3;
const Mat4 = m3d.Mat4;

pub const VertexInputDescription = struct {
    bindings: []const c.VkVertexInputBindingDescription,
    attributes: []const c.VkVertexInputAttributeDescription,

    flags: c.VkPipelineVertexInputStateCreateFlags = 0,
};

pub const Vertex = struct {
    position: Vec3,
    normal: Vec3,
    color: Vec3,
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
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            }),
            std.mem.zeroInit(c.VkVertexInputAttributeDescription, .{
                .location = 3,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "uv"),
            }),
        },
    };
};

pub const BoundingBox = struct {
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

    pub inline fn translate(self: Self, mat: Mat4) Self {
        return .{
            .mins = mat.translate(self.mins),
            .maxs = mat.translate(self.maxs),
        };
    }
};

pub const Mesh = struct {
    vertices: []Vertex,
    bounds: BoundingBox,
    vertex_buffer: AllocatedBuffer = undefined,
};

const obj_loader = @import("obj_loader.zig");

pub fn load_from_obj(allocator: std.mem.Allocator, filepath: []const u8) Mesh {
    var obj_mesh = obj_loader.parse_file(allocator, filepath) catch |err| {
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
        .vertices = vb.vertices.toOwnedSlice() catch @panic("Failed to make owned slice"),
        .bounds = vb.bounds,
    };
}

pub fn load_from_obj2(a: std.mem.Allocator, filepath: []const u8) Mesh {
    var err: c.ufbx_error = std.mem.zeroes(c.ufbx_error);
    const scene = c.ufbx_load_file(filepath.ptr, &.{}, &err);
    if (scene == null) {
        std.log.err("Failed to load obj file: {s}", .{err.description.data});
        unreachable;
    }
    defer c.ufbx_free_scene(scene);

    std.log.debug("{any}", .{scene});
    // var vertices = std.ArrayList(Vertex).init(a);
    for (scene.*.root_node.*.children.data[0..scene.*.root_node.*.children.count]) |*node| {
        std.debug.print("Object: {s}\n", .{node.*.*.attrib.*.name.data});
        const mesh = node.*.*.mesh;
        if (mesh == null) {
            continue;
        }
        std.debug.print("-> mesh with {} faces\n-> materials {}\n", .{ mesh.*.faces.count, mesh.*.face_groups.count });
    }

    // for (uint32_t face_index : part->face_indices) {
    //     ufbx_face face = mesh->faces[face_index];
    //
    //     // Triangulate the face into `tri_indices[]`.
    //     uint32_t num_tris = ufbx_triangulate_face(
    //         tri_indices.data(), tri_indices.size(), mesh, face);
    //
    //     // Iterate over each triangle corner contiguously.
    //     for (size_t i = 0; i < num_tris * 3; i++) {
    //         uint32_t index = tri_indices[i];
    //
    //         Vertex v;
    //         v.position = mesh->vertex_position[index];
    //         v.normal = mesh->vertex_normal[index];
    //         v.uv = mesh->vertex_uv[index];
    //         vertices.push_back(v);
    //     }
    // }
    //     for (mesh.*.faces.data[0..mesh.*.faces.count]) |face| {
    //         vertices
    //         vertices.append(.{
    //             .position = vert.unnamed_0.v,
    //             .normal = ,
    //         });
    //     }
    // }
    // var vertices = std.ArrayList(Vertex).init(a);
    //
    // for (obj_mesh.objects) |object| {
    //     var index_count: usize = 0;
    //     for (object.face_vertices) |face_vx_count| {
    //         if (face_vx_count < 3) {
    //             @panic("Face has fewer than 3 vertices. Not a valid polygon.");
    //         }
    //
    //         for (0..face_vx_count) |vx_index| {
    //             const obj_index = object.indices[index_count];
    //             const pos = obj_mesh.vertices[obj_index.vertex];
    //             const nml = obj_mesh.normals[obj_index.normal];
    //             const uvs = obj_mesh.uvs[obj_index.uv];
    //
    //             const vx = Vertex{
    //                 .position = Vec3.make(pos[0], pos[1], pos[2]),
    //                 .normal = Vec3.make(nml[0], nml[1], nml[2]),
    //                 .color = Vec3.make(nml[0], nml[1], nml[2]),
    //                 .uv = Vec2.make(uvs[0], 1.0 - uvs[1]),
    //             };
    //
    //             // Triangulate the polygon
    //             if (vx_index > 2) {
    //                 const v0 = vertices.items[vertices.items.len - 3];
    //                 const v1 = vertices.items[vertices.items.len - 1];
    //                 vertices.append(v0) catch @panic("OOM");
    //                 vertices.append(v1) catch @panic("OOM");
    //             }
    //
    //             vertices.append(vx) catch @panic("OOM");
    //
    //             index_count += 1;
    //         }
    //     }
    // }

    return load_from_obj(a, filepath);

    // return Mesh{
    //     .vertices = vertices.toOwnedSlice() catch @panic("Failed to make owned slice"),
    // };
}
