const std = @import("std");
const Allocator = std.mem.Allocator;
const obj = @import("obj");
const vk = @import("vulkan");

const assert = @import("../assert.zig");
const yume = @import("../root.zig");
const Mat4 = yume.math.Mat4;
const Vec3 = yume.math.Vec3;
const Vec2 = yume.math.Vec2;
const GraphicsContext = @import("./vulkan/graphics_context.zig").GraphicsContext;
const Renderer = @import("./vulkan/renderer.zig").Renderer();
const VulkanBuffer = @import("./vulkan/VulkanBuffer.zig");

const Vertex = @import("Vertex.zig");

const Self = @This();

vertex_buffer: VulkanBuffer = undefined,
vertex_count: u32 = 0,

has_index_buffer: bool = false,
index_buffer: VulkanBuffer = undefined,
index_count: u32 = 0,

pub fn init(renderer: *Renderer, vertices: []const Vertex, indices: []const u32) !Self {
    var self: Self = Self{};
    try self.createVertexBuffers(renderer, vertices);
    try self.createIndexBuffers(renderer, indices);
    return self;
}

pub fn deinit(self: *Self) void {
    self.vertex_buffer.deinit();
    if (self.has_index_buffer) {
        self.index_buffer.deinit();
    }
}

pub fn fromFile(comptime filepath: []const u8, renderer: *Renderer, a: Allocator) !Self {
    _ = a;
    var ha = std.heap.HeapAllocator.init();
    const allocator = ha.allocator();
    std.debug.print("HERE: {any}\n", .{allocator});
    const model = try obj.parseObj(allocator, @embedFile("../" ++ filepath));
    std.debug.print("fails>?: {any}\n", .{allocator});
    std.debug.print("Loaded: {s} with {any} vertices\n {any}\n", .{ filepath, model.vertices.len, renderer });

    var vertices = std.ArrayList(Vertex).init(allocator);
    defer vertices.deinit();
    var indices = std.ArrayList(u32).init(allocator);
    defer indices.deinit();

    var uniques = std.HashMap(Vertex, u32, struct {
        const K = Vertex;
        pub fn hash(_: @This(), key: K) u64 {
            var h = std.hash.Fnv1a_32.init();
            var b: [4]u8 = @bitCast(key.position.x);
            h.update(&b);
            b = @bitCast(key.position.y);
            h.update(&b);
            b = @bitCast(key.position.z);
            h.update(&b);
            return h.final();
        }

        pub fn eql(_: @This(), lhs: K, rhs: K) bool {
            return lhs.position.eql(rhs.position) and lhs.color.eql(rhs.color) and lhs.normal.eql(rhs.normal) and lhs.uv.eql(rhs.uv);
        }
    }, std.hash_map.default_max_load_percentage).init(allocator);
    defer uniques.deinit();

    for (model.meshes) |mesh| {
        for (mesh.indices) |index| {
            const vix = index.vertex.?;
            var vertex = Vertex{
                .position = Vec3.new(
                    model.vertices[3 * vix + 0],
                    model.vertices[3 * vix + 1],
                    model.vertices[3 * vix + 2],
                ),
                .color = Vec3.new(1, 0, 0),
                .normal = Vec3.as(0),
                .uv = Vec2.as(0),
            };

            if (index.normal) |nix| {
                vertex.normal = Vec3.new(
                    model.normals[3 * nix + 0],
                    model.normals[3 * nix + 1],
                    model.normals[3 * nix + 2],
                );
            }

            if (index.tex_coord) |tix| {
                vertex.uv = Vec2.new(
                    model.tex_coords[2 * tix + 0],
                    model.tex_coords[2 * tix + 1],
                );
            }

            const r = try uniques.getOrPut(vertex);
            if (!r.found_existing) {
                r.value_ptr.* = @as(u32, @truncate(vertices.items.len));
                try vertices.append(vertex);
            }
            try indices.append(r.value_ptr.*);
        }
    }
    return init(renderer, vertices.items, indices.items);
}

pub fn bind(self: *Self, command_buffer: vk.CommandBuffer, gctx: *const GraphicsContext) void {
    gctx.dev.cmdBindVertexBuffers(
        command_buffer,
        0,
        1,
        @ptrCast(&self.vertex_buffer.buffer),
        &.{0},
    );

    if (self.has_index_buffer) {
        gctx.dev.cmdBindIndexBuffer(command_buffer, self.index_buffer.buffer, 0, .uint32);
    }
}

pub fn draw(self: *Self, command_buffer: vk.CommandBuffer, gctx: *const GraphicsContext) void {
    if (self.has_index_buffer) {
        gctx.dev.cmdDrawIndexed(command_buffer, self.index_count, 1, 0, 0, 0);
    } else {
        gctx.dev.cmdDraw(command_buffer, self.vertex_count, 1, 0, 0);
    }
}

fn createVertexBuffers(self: *Self, renderer: *Renderer, vertices: []const Vertex) !void {
    self.vertex_count = @as(u32, @truncate(vertices.len));
    assert.assert(self.vertex_count >= 3, "Vertex count must be at least 3", .{});
    const buffer_size: vk.DeviceSize = @sizeOf(Vertex) * self.vertex_count;
    const vertex_size: u32 = @sizeOf(Vertex);

    var staging_buffer: VulkanBuffer = try VulkanBuffer.init(
        renderer,
        vertex_size,
        self.vertex_count,
        .{ .transfer_src_bit = true },
        .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        1,
    );
    try staging_buffer.map(.{});
    staging_buffer.writeToBuffer(.{ .data = vertices.ptr });

    self.vertex_buffer = try VulkanBuffer.init(
        renderer,
        vertex_size,
        self.vertex_count,
        .{ .vertex_buffer_bit = true, .transfer_dst_bit = true },
        .{ .device_local_bit = true },
        1,
    );

    try renderer.copyBuffer(self.vertex_buffer.buffer, staging_buffer.buffer, buffer_size);
}

fn createIndexBuffers(self: *Self, renderer: *Renderer, indices: []const u32) !void {
    self.index_count = @as(u32, @truncate(indices.len));
    self.has_index_buffer = self.index_count > 0;

    if (!self.has_index_buffer) {
        return;
    }

    const buffer_size = @sizeOf(u32) * self.index_count;
    const index_size = @sizeOf(u32);

    var staging_buffer = try VulkanBuffer.init(
        renderer,
        index_size,
        self.index_count,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        1,
    );

    try staging_buffer.map(.{});
    staging_buffer.writeToBuffer(.{ .data = indices.ptr });

    self.index_buffer = try VulkanBuffer.init(
        renderer,
        index_size,
        self.index_count,
        .{ .index_buffer_bit = true, .transfer_dst_bit = true },
        .{ .device_local_bit = true },
        1,
    );

    try renderer.copyBuffer(self.index_buffer.buffer, staging_buffer.buffer, buffer_size);
}
