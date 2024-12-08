const std = @import("std");
const vk = @import("vulkan");
const c = @cImport({
    @cInclude("string.h");
});

const debugAssert = @import("../../assert.zig").debugAssert;
const GraphicsContext = @import("graphics_context.zig").GraphicsContext;
const Renderer = @import("renderer.zig").Renderer();

const Self = @This();
gctx: *GraphicsContext,
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
    renderer: *Renderer,
    instance_size: vk.DeviceSize,
    instance_count: u32,
    usage_flags: vk.BufferUsageFlags,
    memory_property_flags: vk.MemoryPropertyFlags,
    min_offset_alignment: vk.DeviceSize,
) !Self {
    const alignment_size = getAlignment(instance_size, min_offset_alignment);
    const buffer_size = alignment_size * instance_count;
    const buffer_handle = try renderer.gctx.createBuffer(buffer_size, usage_flags, memory_property_flags);
    return .{
        .gctx = &renderer.gctx,
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
    self.gctx.dev.destroyBuffer(self.buffer, null);
    self.gctx.dev.freeMemory(self.memory, null);
}

/// Map a memory range of this buffer. If successful, mapped points to the specified buffer range.
///
/// @param[in] options.size (Optional) Size of the memory range to map. Pass VK_WHOLE_SIZE to map the complete
/// buffer range.
/// @param[in] options.offset (Optional) Byte offset from beginning
pub fn map(self: *Self, options: MapOptions) !void {
    debugAssert(self.buffer != .null_handle and self.memory != .null_handle, "Called map on buffer before initialization.", .{});
    self.mapped = try self.gctx.dev.mapMemory(self.memory, options.offset, options.size, .{});
}

/// Unmap a mapped memory range
///
/// @note Does not return a result as vkUnmapMemory can't fail
pub fn unmap(self: *Self) void {
    if (self.mapped != null) {
        self.gctx.dev.unmapMemory(self.memory);
        self.mapped = null;
    }
}

// Copies the specified data to the mapped buffer. Default value writes whole buffer range
//
// @param[in] data Pointer to the data to copy
// @param size (Optional) Size of the data to copy. Pass vk.WHOLE_SIZE to flush the complete buffer
// range.
// @param offset (Optional) Byte offset from beginning of mapped region
pub fn writeToBuffer(self: *Self, options: struct { data: *const anyopaque, size: vk.DeviceSize = vk.WHOLE_SIZE, offset: vk.DeviceSize = 0 }) void {
    debugAssert(self.mapped != null, "Cannot copy to unmapped buffer", .{});
    if (options.size == vk.WHOLE_SIZE) {
        _ = c.memcpy(self.mapped, options.data, self.buffer_size);
    } else {
        var memOffset = @as([*]u8, @ptrCast(self.mapped));
        memOffset += options.offset;
        _ = c.memcpy(memOffset, options.data, options.size);
    }
}

// Flush a memory range of the buffer to make it visible to the device
//
// @note Only required for non-coherent memory
//
// @param size (Optional) Size of the memory range to flush. Pass vk.WHOLE_SIZE to flush the
// complete buffer range.
// @param offset (Optional) Byte offset from beginning
//
// @return VkResult of the flush call
pub fn flush(self: *Self, options: struct { size: vk.DeviceSize = vk.WHOLE_SIZE, offset: vk.DeviceSize = 0 }) !void {
    const mapped_range = vk.MappedMemoryRange{
        .memory = self.memory,
        .offset = options.offset,
        .size = options.size,
    };
    try self.gctx.dev.flushMappedMemoryRanges(1, &.{mapped_range});
}

/// Create a buffer info descriptor
///
/// @param options.size (Optional) Size of the memory range of the descriptor
/// @param options.offset (Optional) Byte offset from beginning
///
/// @return DescriptorImageInfo of specified offset and range
///
pub fn descriptorInfo(self: *Self, options: DescriptorInfoOption) vk.DescriptorBufferInfo {
    return .{
        .buffer = self.buffer,
        .offset = options.offset,
        .range = options.size,
    };
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

const MapOptions = struct {
    size: vk.DeviceSize = vk.WHOLE_SIZE,
    offset: vk.DeviceSize = 0,
};

const DescriptorInfoOption = struct {
    size: vk.DeviceSize = vk.WHOLE_SIZE,
    offset: vk.DeviceSize = 0,
};
