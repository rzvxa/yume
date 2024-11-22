const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const backend = @import("../../constants.zig").backend;

const assert = @import("../../assert.zig").assert;
const debugAssert = @import("../../assert.zig").debugAssert;
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

pub inline fn aspectRatio(self: *const Self) f32 {
    return self.swapchain.extentAspectRatio();
}

pub inline fn currentCommandBuffer(self: *const Self) vk.CommandBuffer {
    debugAssert(self.is_frame_started, "Cannot get command buffer when frame is not in progress.", .{});
    return self.command_buffers[self.current_frame_index];
}

pub fn beginFrame(self: *Self) !?vk.CommandBuffer {
    assert(!self.is_frame_started, "Can not call `beginFrame` while a frame is already in progress.", .{});
    const r = try self.swapchain.acquireNextImage();
    const result = r.result;
    self.current_image_index = r.image_index;
    if (result == .error_out_of_date_khr) {
        try self.recreateSwapchain();
        return null;
    }

    if (result != .success and result != .suboptimal_khr) {
        return error.FailedToAcquireSwapchainImage;
    }

    self.is_frame_started = true;
    const command_buffer = self.currentCommandBuffer();

    const begin_info = vk.CommandBufferBeginInfo{};

    try self.device.device.beginCommandBuffer(command_buffer, &begin_info);

    return command_buffer;
}

pub fn endFrame(self: *Self) !void {
    assert(self.is_frame_started, "Can not call `endFrame` while a frame is not in progress.", .{});
    var command_buffer = self.currentCommandBuffer();
    try self.device.device.endCommandBuffer(command_buffer);

    const result = try self.swapchain.submitCommandBuffer(&command_buffer, &self.current_image_index);
    if (result == .error_out_of_date_khr or result == .suboptimal_khr or self.window.frame_buffer_resized) {
        self.window.frame_buffer_resized = false;
        try self.recreateSwapchain();
    } else if (result != .success) {
        return error.FailedToAcquireSwapchainImage;
    }
    self.is_frame_started = false;
    self.current_frame_index = (self.current_frame_index + 1) % backend.max_frames_in_flight;
}

pub fn beginSwapchainRenderPass(self: *const Self, command_buffer: vk.CommandBuffer) void {
    assert(self.is_frame_started, "Can not call `beginSwapchainRenderPass` while frame is not in progress", .{});
    assert(command_buffer == self.currentCommandBuffer(), "Can not begin render pass on command bufferfrom a different frame", .{});

    const clear_values: [2]vk.ClearValue = .{
        .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
        .{ .depth_stencil = .{ .depth = 1, .stencil = 0 } },
    };

    const render_pass_info = vk.RenderPassBeginInfo{
        .render_pass = self.swapchain.render_pass,
        .framebuffer = self.swapchain.swap_chain_frame_buffers[self.current_image_index],

        .render_area = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapchain.swap_chain_extent,
        },
        .clear_value_count = 2,
        .p_clear_values = &clear_values,
    };

    self.device.device.cmdBeginRenderPass(command_buffer, &render_pass_info, .@"inline");

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @bitCast(self.swapchain.swap_chain_extent.width),
        .height = @bitCast(self.swapchain.swap_chain_extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swapchain.swap_chain_extent,
    };

    self.device.device.cmdSetViewport(command_buffer, 0, 1, @ptrCast(&viewport));
    self.device.device.cmdSetScissor(command_buffer, 0, 1, @ptrCast(&scissor));
}

pub fn endSwapchainRenderPass(self: *const Self, command_buffer: vk.CommandBuffer) void {
    assert(self.is_frame_started, "Can not call endSwapChainRenderPass while frame is not in progress", .{});
    assert(command_buffer == self.currentCommandBuffer(), "Can not end render pass on command buffer from a different frame", .{});

    self.device.device.cmdEndRenderPass(command_buffer);
}

fn recreateSwapchain(self: *Self) !void {
    const extent = self.window.getValidExtnet();
    try self.device.device.deviceWaitIdle();
    var old_swapchain = self.swapchain;
    defer old_swapchain.deinit();
    self.swapchain = try VulkanSwapChain.init(self.device, extent, &old_swapchain, self.allocator);
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
