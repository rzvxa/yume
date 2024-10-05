const std = @import("std");
const vk = @import("vulkan");

const debugAssert = @import("../../assert.zig").debugAssert;
const VulkanDevice = @import("VulkanDevice.zig");

const Self = @This();
device: *VulkanDevice,
mapped: ?*anyopaque = null,
buffer: vk.Buffer,
memory: vk.DeviceMemory,

buffer_size: vk.DeviceSize,
instance_count: u32,
instance_size: vk.DeviceSize,
alignment_size: vk.DeviceSize,
usage_flags: vk.BufferUsageFlags,
memory_property_flags: vk.MemoryPropertyFlags,

pub fn init(
    device: VulkanDevice,
    instance_size: vk.DeviceSize,
    instance_count: u32,
    usage_flags: vk.BufferUsageFlags,
    memory_property_flags: vk.MemoryPropertyFlags,
    min_offset_alignment: vk.DeviceSize,
) !Self {
    const alignment_size = getAlignment(instance_size, min_offset_alignment);
    const buffer_size = alignment_size * instance_count;
    const buffer_handle = try device.createBuffer(buffer_size, usage_flags, memory_property_flags);
    return .{
        .device = device,
        .buffer = buffer_handle.buf,
        .memory = buffer_handle.mem,

        .buffer_size = buffer_size,
        .instance_count = instance_count,
        .instance_size = instance_size,
        .alignment_size = alignment_size,
        .usage_flags = usage_flags,
        .memory_property_flags = memory_property_flags,
    };
}

pub fn deinit(self: *Self) void {
    self.unmap();
    self.device.destroyBuffer(self.buffer, null);
    self.device.freeMemory(self.memory, null);
}

/// Map a m_memory range of this buffer. If successful, m_mapped points to the specified buffer range.
///
/// @param[in] size Size of the m_memory range to map. Pass VK_WHOLE_SIZE to map the complete
/// buffer range.
/// @param[in] offset Byte offset from beginning
pub fn map(self: *Self, size: vk.DeviceSize, offset: vk.DeviceSize) !void {
    debugAssert(self.buffer != null and self.memory != null, "Called map on buffer before initialization.");
    self.mapped = try self.device.mapMemory(self.memory, offset, size, 0);
}

/// Unmap a m_mapped m_memory range
///
/// @note Does not return a result as vkUnmapMemory can't fail
pub fn unmap(self: *Self) void {
    if (self.mapped != null) {
        self.device.unmapMemory(self.memory);
        self.mapped = null;
    }
}

/// Returns the minimum instance size required to be compatible with devices minOffsetAlignment
///
/// @param[in] instanceSize The size of an instance
/// @param[in] minOffsetAlignment The minimum required alignment, in bytes, for the offset member (eg
/// minUniformBufferOffsetAlignment)
///
/// @return VkResult of the buffer mapping call
pub fn getAlignment(instance_size: vk.DeviceSize, min_offset_alignment: vk.DeviceSize) vk.DeviceSize {
    if (min_offset_alignment > 0) {
        return (instance_size + min_offset_alignment - 1) & ~(min_offset_alignment - 1);
    }
    return instance_size;
}
