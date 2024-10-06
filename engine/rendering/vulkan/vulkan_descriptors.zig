const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;
const VulkanDevice = @import("VulkanDevice.zig");

pub const VulkanDescriptorPool = struct {
    const Self = @This();
    pub const InitOptions = struct {
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

    pub fn deinit(self: *Self) void {
        self.device.device.destroyDescriptorPool(self.descriptor_pool, null);
    }
};

pub const VulkanDescriptorSetLayout = struct {
    const Self = @This();
    pub const BindingOptions = struct {
        binding: u32,
        type: vk.DescriptorType,
        stage_flags: vk.ShaderStageFlags,
        count: u32 = 1,
    };

    device: *VulkanDevice,
    descriptor_set_layout: vk.DescriptorSetLayout,
    bindings: std.AutoHashMap(u32, vk.DescriptorSetLayoutBinding),

    // `Self` becomes the owner of the data
    pub fn init(device: *VulkanDevice, bindings: []BindingOptions, allocator: Allocator) !Self {
        var bind_map = std.AutoHashMap(u32, vk.DescriptorSetLayoutBinding).init(allocator);
        const set_layout_bindings: []vk.DescriptorSetLayoutBinding =
            blk: {
            var bindings_ = try allocator.alloc(vk.DescriptorSetLayoutBinding, bindings.len);
            for (bindings, 0..) |opts, ix| {
                const layout_binding = vk.DescriptorSetLayoutBinding{
                    .binding = opts.binding,
                    .descriptor_type = opts.type,
                    .descriptor_count = opts.count,
                    .stage_flags = opts.stage_flags,
                };
                bindings_[ix] = layout_binding;
                try bind_map.put(opts.binding, layout_binding);
            }
            break :blk bindings_;
        };
        defer allocator.free(set_layout_bindings);
        const descriptor_set_layout_info = vk.DescriptorSetLayoutCreateInfo{
            .binding_count = @as(u32, @truncate(set_layout_bindings.len)),
            .p_bindings = set_layout_bindings.ptr,
        };
        const descriptor_set_layout = try device.device.createDescriptorSetLayout(&descriptor_set_layout_info, null);
        return .{
            .device = device,
            .descriptor_set_layout = descriptor_set_layout,
            .bindings = bind_map,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.device.destroyDescriptorSetLayout(self.descriptor_set_layout, null);
        self.bindings.deinit();
    }
};
