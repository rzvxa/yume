const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const backend = @import("../../constants.zig").backend;

const Allocator = std.mem.Allocator;

const List = @import("../../collections/mod.zig").List;
const VulkanWindow = @import("../../window/vulkan/VulkanWindow.zig");
const VulkanDevice = @import("VulkanDevice.zig");
const VulkanSwapChain = @import("VulkanSwapChain.zig");

const Self = @This();

allocator: Allocator,

window: *VulkanWindow,
device: *VulkanDevice,

swapchain: VulkanSwapChain,
command_buffers: []vk.CommandBuffer,

current_image_index: u32 = 0,
current_frame_index: u32 = 0,
is_frame_started: bool = false,

pub fn init(device: *VulkanDevice, window: *VulkanWindow, allocator: Allocator) !Self {
    return .{
        .allocator = allocator,

        .device = device,
        .window = window,

        .swapchain = try VulkanSwapChain.init(device, window.getValidExtnet(), null, allocator),
        .command_buffers = try createCommandBuffers(device, allocator),
    };
}

pub fn deinit(self: *Self) void {
    const dev = &self.device.device;
    dev.freeCommandBuffers(
        self.device.command_pool,
        @as(u32, @truncate(self.command_buffers.len)),
        self.command_buffers.ptr,
    );
    self.allocator.free(self.command_buffers);
}

pub fn aspectRatio(self: *const Self) f32 {
    return self.swapchain.extentAspectRatio();
}

fn recreateSwapchain(self: *Self) !void {
    const extent = self.window.getValidExtnet();
    try self.device.device.deviceWaitIdle();
    var old_swapchain = self.swapchain;
    defer old_swapchain.deinit();
    self.swapchain = VulkanSwapChain.init(self.device, extent, &old_swapchain, self.allocator);
    if (old_swapchain.compareSwapFormats(&self.swapchain)) {
        return error.SwapchainImageOrDepthFormatChanged;
    }
}

fn createCommandBuffers(device: *VulkanDevice, allocator: Allocator) ![]vk.CommandBuffer {
    const command_buffers = try allocator.alloc(vk.CommandBuffer, backend.max_frames_in_flight);

    const alloc_info = vk.CommandBufferAllocateInfo{
        .level = .primary,
        .command_pool = device.command_pool,
        .command_buffer_count = @as(u32, @truncate(command_buffers.len)),
    };

    try device.device.allocateCommandBuffers(&alloc_info, command_buffers.ptr);
    return command_buffers;
}
