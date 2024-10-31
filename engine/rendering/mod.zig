const std = @import("std");
const Allocator = std.mem.Allocator;

const frame = @import("frame.zig");
pub const SimpleRenderPipeline = @import("SimpleRenderPipeline.zig");
pub const GlobalUbo = frame.GlobalUbo;

pub const RenderBackendApi = enum { vulkan };
pub const RenderBackend = struct {
    api: RenderBackendApi,
    max_frames_in_flight: comptime_int,
};

pub fn Renderer(comptime backend: RenderBackend) type {
    return switch (backend.api) {
        .vulkan => {
            return @import("vulkan/VulkanRenderer.zig");
        },
    };
}

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

pub fn DescriptorSetLayout(comptime backend: RenderBackend) type {
    switch (backend.api) {
        .vulkan => {
            return @import("vulkan/vulkan_descriptors.zig").VulkanDescriptorSetLayout;
        },
    }
}

pub fn DescriptorWriter(comptime backend: RenderBackend) type {
    switch (backend.api) {
        .vulkan => {
            return @import("vulkan/vulkan_descriptors.zig").VulkanDescriptorWriter;
        },
    }
}

pub fn GraphicBuffer(comptime backend: RenderBackend) type {
    switch (backend.api) {
        .vulkan => {
            return @import("vulkan/VulkanBuffer.zig");
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

pub const DSize = u64;

// TODO: abstract these
const vk = @import("vulkan");
pub const MemoryPropertyFlags = vk.MemoryPropertyFlags;
pub const BufferUsageFlags = vk.BufferUsageFlags;
pub const DescriptorBufferInfo = vk.DescriptorBufferInfo;
pub const DescriptorSet = vk.DescriptorSet;
