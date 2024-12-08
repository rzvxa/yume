const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const math = @import("../root.zig");

const Self = @This();
position: math.Vec3,
color: math.Vec3,
normal: math.Vec3,
uv: math.Vec2,

pub const binding_description = vk.VertexInputBindingDescription{
    .binding = 0,
    .stride = @sizeOf(Self),
    .input_rate = .vertex,
};

pub const attribute_description = [_]vk.VertexInputAttributeDescription{
    .{
        .binding = 0,
        .location = 0,
        .format = .r32g32b32_sfloat,
        .offset = @offsetOf(Self, "position"),
    },
    .{
        .binding = 0,
        .location = 1,
        .format = .r32g32b32_sfloat,
        .offset = @offsetOf(Self, "color"),
    },
    .{
        .binding = 0,
        .location = 2,
        .format = .r32g32b32_sfloat,
        .offset = @offsetOf(Self, "normal"),
    },
    .{
        .binding = 0,
        .location = 3,
        .format = .r32g32_sfloat,
        .offset = @offsetOf(Self, "uv"),
    },
};
