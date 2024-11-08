const std = @import("std");
const vk = @import("vulkan");

const backend = @import("../../constants.zig").backend;

const Allocator = std.mem.Allocator;

const List = @import("../../collections/mod.zig").List;

const VulkanDevice = @import("VulkanDevice.zig");

const Self = @This();

allocator: Allocator,

swap_chain_image_format: vk.Format,
swap_chain_depth_format: vk.Format,
swap_chain_extent: vk.Extent2D,

swap_chain_frame_buffers: []vk.Framebuffer,
render_pass: vk.RenderPass,

depth_images: []vk.Image,
depth_image_memories: []vk.DeviceMemory,
depth_image_views: []vk.ImageView,
swap_chain_images: []vk.Image,
swap_chain_image_views: []vk.ImageView,

device: *VulkanDevice,
window_extent: vk.Extent2D,

swap_chain: vk.SwapchainKHR,

// image_available_semaphores: []vk.Semaphore,
// render_finished_semaphores: []vk.Semaphore,
// in_flight_fences: []vk.Fence,
// images_in_flight: []vk.Fence,

current_frame: usize = 0,

pub fn init(
    device: *VulkanDevice,
    window_extent: vk.Extent2D,
    old_swap_chain: ?*Self,
    allocator: Allocator,
) !Self {
    const depth_format = try findDepthFormat(device);
    const sc_res = try createSwapChain(device, window_extent, old_swap_chain, allocator);
    const swap_chain_image_views = try createImageViews(device, &sc_res, allocator);
    const render_pass = try createRenderPass(device, &sc_res, depth_format);
    const cdr_res = try createDepthResources(device, &sc_res, depth_format, allocator);
    const swap_chain_frame_buffers = try createFramebuffers(device, render_pass, &sc_res, swap_chain_image_views, &cdr_res, allocator);
    return .{
        .allocator = allocator,

        .device = device,
        .window_extent = window_extent,

        .render_pass = render_pass,

        .swap_chain_frame_buffers = swap_chain_frame_buffers,

        .swap_chain = sc_res.swap_chain,
        .swap_chain_images = sc_res.swap_chain_images,
        .swap_chain_extent = sc_res.swap_chain_extent,
        .swap_chain_image_views = swap_chain_image_views,
        .swap_chain_image_format = sc_res.swap_chain_image_format,

        .depth_images = cdr_res.depth_images,
        .depth_image_memories = cdr_res.depth_image_memories,
        .depth_image_views = cdr_res.depth_image_views,
        .swap_chain_depth_format = depth_format,
    };
}

pub fn deinit(self: *Self) void {
    const dev = &self.device.device;

    for (0..self.swap_chain_image_views.len) |i| {
        dev.destroyImageView(self.swap_chain_image_views.len[i], null);
    }
    self.allocator.free(self.swap_chain_image_views.len);

    if (self.swap_chain != null) {
        dev.destroySwapchainKHR(self.swap_chain, null);
    }

    for (0..self.depth_images) |i| {
        dev.destroyImageView(self.depth_image_views[i], null);
        dev.destroyImage(self.depth_images[i], null);
        dev.freeMemory(self.depth_image_memories[i], null);
    }

    for (0..self.swap_chain_frame_buffers.len) |i| {
        dev.destroyFramebuffer(self.swap_chain_frame_buffers[i], null);
    }

    dev.destroyRenderPass(self.render_pass, null);

    // cleanup synchronization objects
    for (0..backend.max_frames_in_flight) |i| {
        dev.destroySemaphore(self.render_finished_semaphores[i], null);
        dev.destroySemaphore(self.image_available_semaphores[i], null);
        dev.destroyFence(self.in_flight_fences[i], null);
    }

    self.swap_chain_frame_buffers.deinit();

    self.depth_images.deinit();
    self.depth_image_memories.deinit();
    self.depth_image_views.deinit();
    self.swap_chain_images.deinit();
    self.swap_chain_image_views.deinit();

    self.image_available_semaphores.deinit();
    self.render_finished_semaphores.deinit();
    self.in_flight_fences.deinit();
    self.images_in_flight.deinit();
}

pub fn compareSwapFormats(self: *const Self, other: *const Self) bool {
    return self.swap_chain.swap_chain_depth_format == other.swap_chain.swap_chain_depth_format and
        self.swap_chain.swap_chain_image_format == other.swap_chain_image_format;
}

pub fn extentAspectRatio(self: *const Self) f32 {
    return @as(f32, @bitCast(self.swap_chain_extent.width)) / @as(f32, @bitCast(self.swap_chain_extent.height));
}

fn createSwapChain(
    device: *VulkanDevice,
    window_extent: vk.Extent2D,
    old_swap_chain: ?*Self,
    allocator: Allocator,
) !CreateSwapchainResult {
    const swap_chain_support = try device.getSwapChainSupport();

    const surface_format = chooseSwapSurfaceFormat(&swap_chain_support.formats);
    const present_mode = chooseSwapPresentMode(&swap_chain_support.present_modes);
    const extent = chooseSwapExtent(window_extent, &swap_chain_support.capabilities);

    var image_count = swap_chain_support.capabilities.min_image_count + 1;
    if (swap_chain_support.capabilities.max_image_count > 0 and image_count > swap_chain_support.capabilities.max_image_count) {
        image_count = swap_chain_support.capabilities.max_image_count;
    }

    const indices = try device.findPhysicalQueueFamilies();
    const queue_family_indices: [2]u32 = .{ indices.graphics_family, indices.present_family };

    const specialized_data: struct {
        image_sharing_mode: vk.SharingMode,
        queue_family_index_count: u32,
        p_queue_family_indices: ?[*]const u32,
    } = if (indices.graphics_family != indices.present_family) .{
        .image_sharing_mode = .concurrent,
        .queue_family_index_count = 2,
        .p_queue_family_indices = &queue_family_indices,
    } else .{
        .image_sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = null,
    };
    const create_info = vk.SwapchainCreateInfoKHR{
        .surface = device.surface,
        .min_image_count = image_count,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },

        .image_sharing_mode = specialized_data.image_sharing_mode,
        .queue_family_index_count = specialized_data.queue_family_index_count,
        .p_queue_family_indices = specialized_data.p_queue_family_indices,

        .pre_transform = swap_chain_support.capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },

        .present_mode = present_mode,
        .clipped = vk.TRUE,

        .old_swapchain = if (old_swap_chain) |old| old.swap_chain else .null_handle,
    };

    const swap_chain = try device.device.createSwapchainKHR(&create_info, null);

    _ = try device.device.getSwapchainImagesKHR(swap_chain, &image_count, null);
    const swap_chain_images = try allocator.alloc(vk.Image, image_count);
    _ = try device.device.getSwapchainImagesKHR(swap_chain, &image_count, swap_chain_images.ptr);

    return .{
        .swap_chain = swap_chain,
        .swap_chain_images = swap_chain_images,
        .swap_chain_image_format = surface_format.format,
        .swap_chain_extent = extent,
    };
}

fn createImageViews(device: *VulkanDevice, swapchain_result: *const CreateSwapchainResult, allocator: Allocator) ![]vk.ImageView {
    const image_count = swapchain_result.swap_chain_images.len;
    var swap_chain_image_views = try allocator.alloc(vk.ImageView, image_count);
    for (0..image_count) |i| {
        const view_info = vk.ImageViewCreateInfo{
            .image = swapchain_result.swap_chain_images[i],
            .view_type = .@"2d",
            .format = swapchain_result.swap_chain_image_format,
            .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity,
            },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        swap_chain_image_views[i] = try device.device.createImageView(&view_info, null);
    }
    return swap_chain_image_views;
}

fn createRenderPass(
    device: *VulkanDevice,
    swapchain_result: *const CreateSwapchainResult,
    depth_format: vk.Format,
) !vk.RenderPass {
    const depth_attachment = vk.AttachmentDescription{
        .format = depth_format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .dont_care,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .depth_stencil_attachment_optimal,
    };

    const depth_attachment_ref = vk.AttachmentReference{
        .attachment = 1,
        .layout = .depth_stencil_attachment_optimal,
    };

    const color_attachment = vk.AttachmentDescription{
        .format = swapchain_result.swap_chain_image_format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_store_op = .dont_care,
        .stencil_load_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref: [1]vk.AttachmentReference = .{.{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    }};

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = &color_attachment_ref,
        .p_depth_stencil_attachment = &depth_attachment_ref,
    };

    const dependency = vk.SubpassDependency{
        .src_subpass = 0,
        .dst_subpass = 0,
        .src_stage_mask = .{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true },
        .dst_stage_mask = .{ .color_attachment_output_bit = true, .early_fragment_tests_bit = true },
        .src_access_mask = .{},
        .dst_access_mask = .{ .color_attachment_write_bit = true, .depth_stencil_attachment_write_bit = true },
    };

    const attachments: [2]vk.AttachmentDescription = .{ color_attachment, depth_attachment };
    const render_pass_info = vk.RenderPassCreateInfo{
        .attachment_count = @as(u32, @truncate(attachments.len)),
        .p_attachments = &attachments,
        .subpass_count = 1,
        .p_subpasses = &.{subpass},
        .dependency_count = 1,
        .p_dependencies = &.{dependency},
    };

    return try device.device.createRenderPass(&render_pass_info, null);
}

fn createDepthResources(
    device: *VulkanDevice,
    swapchain_result: *const CreateSwapchainResult,
    depth_format: vk.Format,
    allocator: Allocator,
) !CreateDepthResourcesResult {
    const extent = swapchain_result.swap_chain_extent;
    const image_count = swapchain_result.swap_chain_images.len;

    var depth_images = try allocator.alloc(vk.Image, image_count);
    var depth_image_memories = try allocator.alloc(vk.DeviceMemory, image_count);
    var depth_image_views = try allocator.alloc(vk.ImageView, image_count);

    for (0..image_count) |i| {
        const image_info = vk.ImageCreateInfo{
            .image_type = .@"2d",
            .extent = .{
                .width = extent.width,
                .height = extent.height,
                .depth = 1,
            },
            .mip_levels = 1,
            .array_layers = 1,
            .format = depth_format,
            .tiling = .optimal,
            .initial_layout = .undefined,
            .usage = .{ .depth_stencil_attachment_bit = true },
            .samples = .{ .@"1_bit" = true },
            .sharing_mode = .exclusive,
            .flags = .{},
        };

        try device.createImageWithInfo(
            &image_info,
            .{ .device_local_bit = true },
            &depth_images[i],
            &depth_image_memories[i],
        );

        const view_info = vk.ImageViewCreateInfo{
            .image = depth_images[i],
            .view_type = .@"2d",
            .format = depth_format,
            .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity,
            },
            .subresource_range = .{
                .aspect_mask = .{ .depth_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        depth_image_views[i] = try device.device.createImageView(&view_info, null);
    }

    return .{
        .depth_images = depth_images,
        .depth_image_memories = depth_image_memories,
        .depth_image_views = depth_image_views,
    };
}

fn createFramebuffers(
    device: *VulkanDevice,
    render_pass: vk.RenderPass,
    swapchain_result: *const CreateSwapchainResult,
    swapchain_image_views: []vk.ImageView,
    depth_result: *const CreateDepthResourcesResult,
    allocator: Allocator,
) ![]vk.Framebuffer {
    const image_count = swapchain_result.swap_chain_images.len;
    var swap_chain_frame_buffers = try allocator.alloc(vk.Framebuffer, image_count);
    for (0..image_count) |i| {
        const attachments: [2]vk.ImageView = .{ swapchain_image_views[i], depth_result.depth_image_views[i] };

        const swap_chain_extent = swapchain_result.swap_chain_extent;
        const frame_buffer_info = vk.FramebufferCreateInfo{
            .render_pass = render_pass,
            .attachment_count = @as(u32, @truncate(attachments.len)),
            .p_attachments = &attachments,
            .width = swap_chain_extent.width,
            .height = swap_chain_extent.height,
            .layers = 1,
        };

        swap_chain_frame_buffers[i] = try device.device.createFramebuffer(&frame_buffer_info, null);
    }

    return swap_chain_frame_buffers;
}

fn chooseSwapSurfaceFormat(available_formats: *const []vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
    for (available_formats.*) |it| {
        if (it.format == .b8g8r8a8_unorm and it.color_space == .srgb_nonlinear_khr) {
            return it;
        }
    }

    return available_formats.*[0];
}

fn chooseSwapPresentMode(available_present_modes: *const []vk.PresentModeKHR) vk.PresentModeKHR {
    var seen_immediate_mode: ?vk.PresentModeKHR = null;
    for (available_present_modes.*) |mode| {
        if (mode == .mailbox_khr) {
            std.debug.print("Present mode: Mailbox\n", .{});
            return mode;
        }
        if (mode == .immediate_khr) {
            seen_immediate_mode = mode;
        }
    }

    if (seen_immediate_mode) |mode| {
        std.debug.print("Present mode: Immediate\n", .{});
        return mode;
    }

    std.debug.print("Present mode: V-Sync\n", .{});
    return .fifo_khr;
}

fn chooseSwapExtent(window_extent: vk.Extent2D, capabilities: *const vk.SurfaceCapabilitiesKHR) vk.Extent2D {
    if (capabilities.current_extent.width != std.math.maxInt(u32)) {
        return capabilities.current_extent;
    } else {
        var actual_extent = window_extent;
        actual_extent.width = @max(capabilities.min_image_extent.width, @min(capabilities.max_image_extent.width, actual_extent.width));
        actual_extent.height = @max(capabilities.min_image_extent.height, @min(capabilities.max_image_extent.height, actual_extent.height));
        return actual_extent;
    }
}

fn findDepthFormat(device: *const VulkanDevice) !vk.Format {
    const candidates: [3]vk.Format = .{ .d32_sfloat, .d32_sfloat_s8_uint, .d24_unorm_s8_uint };
    return try device.findSupportedFormat(
        &candidates,
        .optimal,
        .{ .depth_stencil_attachment_bit = true },
    );
}

const CreateSwapchainResult = struct {
    swap_chain: vk.SwapchainKHR,
    swap_chain_images: []vk.Image,
    swap_chain_image_format: vk.Format,
    swap_chain_extent: vk.Extent2D,
};

const CreateDepthResourcesResult = struct {
    depth_images: []vk.Image,
    depth_image_memories: []vk.DeviceMemory,
    depth_image_views: []vk.ImageView,
};
