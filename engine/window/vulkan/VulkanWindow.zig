const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const VkInstance = @import("../../rendering/vulkan/VulkanDevice.zig").VkInstance;

const Self = @This();
width: u32,
height: u32,
frame_buffer_resized: bool,
title: [*:0]const u8,
window: glfw.Window,

pub fn init(width: u32, height: u32, title: [*:0]const u8) error{ GLFWInit, WindowCreation, UnsupportedPlatform }!Self {
    if (!glfw.init(.{})) {
        // std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return error.GLFWInit;
    }

    if (!glfw.vulkanSupported()) {
        return error.UnsupportedPlatform;
    }

    const window = glfw.Window.create(800, 600, title, null, null, .{
        .resizable = true,
        .client_api = .no_api,
    }) orelse {
        return error.WindowCreation;
    };

    var self = .{
        .width = width,
        .height = height,
        .title = title,
        .window = window,
        .frame_buffer_resized = false,
    };
    window.setUserPointer(&self);
    window.setFramebufferSizeCallback(Self.framebufferResizeCallback);
    return self;
}

pub fn deinit(self: *Self) void {
    self.window.destroy();
}

pub fn shouldClose(self: *const Self) bool {
    return self.window.shouldClose();
}

pub fn createWindowSurface(self: *Self, vk_instance: vk.Instance, surface: *vk.SurfaceKHR) error{FailedToCreateWindowSurface}!void {
    if (glfw.createWindowSurface(vk_instance, self.window, null, surface) != @intFromEnum(vk.Result.success)) {
        return error.FailedToCreateWindowSurface;
    }
}

pub inline fn getExtent(self: *const Self) vk.Extent2D {
    return .{ .width = self.width, .height = self.height };
}

/// Waits until window extent is non-zero and returns it
pub inline fn getValidExtnet(self: *const Self) vk.Extent2D {
    var extent = self.getExtent();

    while (extent.width == 0 or extent.height == 0) {
        extent = self.getExtent();
        glfw.waitEvents();
    }

    return extent;
}

fn framebufferResizeCallback(window: glfw.Window, width: u32, height: u32) void {
    const vk_window = window.getUserPointer(Self) orelse unreachable;
    vk_window.frame_buffer_resized = true;
    vk_window.width = width;
    vk_window.height = height;
}
