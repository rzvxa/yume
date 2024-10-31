const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const math = @import("../root.zig");

const Self = @This();
position: math.Vec3,
color: math.Vec3,
normal: math.Vec3,
uv: math.Vec2,

pub fn getBindingDescriptions(allocator: Allocator) ![]vk.VertexInputBindingDescription {
    var result = try allocator.alloc(vk.VertexInputBindingDescription, 1);
    result[0] = .{
        .binding = 0,
        .stride = @sizeOf(Self),
        .input_rate = .vertex,
    };
    return result;
}

pub fn getAttributeDescriptions(allocator: Allocator) ![]vk.VertexInputAttributeDescription {
    var result = try allocator.alloc(vk.VertexInputAttributeDescription, 4);
    result[0] = .{
        .location = 0,
        .binding = 0,
        .format = .r32g32b32_sfloat,
        .offset = @offsetOf(Self, "position"),
    };
    result[1] = .{
        .location = 1,
        .binding = 0,
        .format = .r32g32b32_sfloat,
        .offset = @offsetOf(Self, "color"),
    };
    result[2] = .{
        .location = 2,
        .binding = 0,
        .format = .r32g32b32_sfloat,
        .offset = @offsetOf(Self, "normal"),
    };
    result[3] = .{
        .location = 3,
        .binding = 0,
        .format = .r32g32_sfloat,
        .offset = @offsetOf(Self, "uv"),
    };
    return result;
}
