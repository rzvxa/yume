const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;
const VulkanDevice = @import("VulkanDevice.zig");

pub const VulkanDescriptorPool = struct {
    const Self = @This();
    const InitOptions = struct {
        allocator: Allocator,
        device: *VulkanDevice,
        pool_sizes: []const vk.DescriptorPoolSize,
        pool_flags: vk.DescriptorPoolCreateFlags = .{},
        max_sets: u32 = 1000,
    };

    device: *VulkanDevice,
    descriptor_pool: vk.DescriptorPool,

    pub fn init(options: InitOptions) !Self {
        const descriptor_pool_info = vk.DescriptorPoolCreateInfo{
            .pool_size_count = @as(u32, @truncate(options.pool_sizes.len)),
            .p_pool_sizes = options.pool_sizes.ptr,
            .max_sets = options.max_sets,
            .flags = options.pool_flags,
        };

        const device = options.device;
        const descriptor_pool = try device.device.createDescriptorPool(&descriptor_pool_info, null);
        return .{
            .device = device,
            .descriptor_pool = descriptor_pool,
        };
    }
};

const VulkanDescriptorSetLayout = struct {};
