const std = @import("std");
const Allocator = std.mem.Allocator;

pub const RenderBackendApi = enum { vulkan };
pub const RenderBackend = struct {
    api: RenderBackendApi,
    max_frames_in_flight: comptime_int,
};

pub fn Device(comptime backend: RenderBackend) type {
    return switch (backend.api) {
        .vulkan => {
            return @import("vulkan/VulkanDevice.zig");
        },
    };
}

pub fn DescriptorPool(comptime backend: RenderBackend) type {
    switch (backend.api) {
        .vulkan => {
            return @import("vulkan/vulkan_descriptors.zig").VulkanDescriptorPool;
        },
    }
}

pub fn initDefaultDescriptorPool(comptime backend: RenderBackend, device: *Device(backend), allocator: Allocator) !DescriptorPool(backend) {
    return switch (backend.api) {
        .vulkan => {
            return try DescriptorPool(backend).init(.{
                .allocator = allocator,
                .device = device,
                .max_sets = backend.max_frames_in_flight,
                .pool_sizes = &.{
                    .{ .type = .uniform_buffer, .descriptor_count = backend.max_frames_in_flight },
                },
            });
        },
    };
}
