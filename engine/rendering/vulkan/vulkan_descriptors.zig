const std = @import("std");
const vk = @import("vulkan");

const assert = @import("../../assert.zig").assert;
const rendering = @import("../mod.zig");
const DescriptorBufferInfo = rendering.DescriptorBufferInfo;
const DescriptorSet = rendering.DescriptorSet;

const List = @import("../../collections/mod.zig").List;
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

    fn allocateDescriptor(self: *Self, descriptor_set_layout: *vk.DescriptorSetLayout, descriptor: *vk.DescriptorSet) !void {
        const alloc_info = vk.DescriptorSetAllocateInfo{
            .descriptor_pool = self.descriptor_pool,
            .descriptor_set_count = 1,
            .p_set_layouts = @ptrCast(descriptor_set_layout),
        };
        try self.device.device.allocateDescriptorSets(&alloc_info, @ptrCast(descriptor));
    }

    fn freeDescriptors(self: *Self, descriptors: []vk.DescriptorSet) !void {
        self.device.device.freeDescriptorSets(
            self.descriptor_pool,
            @as(u32, @truncate(descriptors.len)),
            descriptors.ptr,
        );
    }

    fn resetPool(self: *Self) void {
        self.device.device.resetDescriptorPool(self.descriptor_pool, .{});
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

pub const VulkanDescriptorWriter = struct {
    const Self = @This();
    allocator: Allocator,
    set_layout: *VulkanDescriptorSetLayout,
    pool: *VulkanDescriptorPool,
    writes: List(vk.WriteDescriptorSet),

    pub fn init(set_layout: *VulkanDescriptorSetLayout, pool: *VulkanDescriptorPool, allocator: Allocator) !Self {
        return .{
            .allocator = allocator,
            .set_layout = set_layout,
            .pool = pool,
            // we almost always write to at least one buffer so lets pre-allocate it.
            .writes = try List(vk.WriteDescriptorSet).initCapacity(allocator, 1),
        };
    }

    pub fn deinit(self: *Self) void {
        self.writes.deinit();
    }

    pub fn writeBuffer(self: *Self, binding: u32, buffer_info: *const DescriptorBufferInfo) !void {
        const binding_description = if (self.set_layout.bindings.getPtr(binding)) |descr|
            descr
        else
            std.debug.panic("Layout does not contain specified binding.", .{});

        assert(binding_description.descriptor_count == 1, "Binding single descriptor infor, but binding expects multiple", .{});
        const write = vk.WriteDescriptorSet{
            .dst_set = .null_handle,
            .dst_binding = binding,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = binding_description.descriptor_type,
            .p_image_info = undefined,
            .p_buffer_info = @ptrCast(buffer_info),
            .p_texel_buffer_view = undefined,
        };
        try self.writes.append(write);
    }

    pub fn flush(self: *Self, set: DescriptorSet) !void {
        var set_ = set;
        try self.pool.allocateDescriptor(&self.set_layout.descriptor_set_layout, &set_);
        self.overwrite(set_);
    }

    pub fn overwrite(self: *Self, set: DescriptorSet) void {
        for (0..self.writes.items.len) |i| {
            self.writes.items[i].dst_set = set;
        }

        self.pool.device.device.updateDescriptorSets(@as(u32, @truncate(self.writes.items.len)), self.writes.items.ptr, 0, null);
    }
};
