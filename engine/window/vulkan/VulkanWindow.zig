const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const VkInstance = @import("../../rendering/vulkan/VulkanDevice.zig").VkInstance;

const Self = @This();
width: u32,
height: u32,
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
    };
    window.setUserPointer(&self);
    window.setFramebufferSizeCallback(Self.framebufferResizeCallback);
    return self;
}

pub fn deinit(self: *Self) void {
    self.window.destroy();
}

pub fn shouldClose(self: *Self) bool {
    return self.window.shouldClose();
}

pub fn createWindowSurface(self: *Self, vk_instance: vk.Instance, surface: *vk.SurfaceKHR) error{FailedToCreateWindowSurface}!void {
    if (glfw.createWindowSurface(vk_instance, self.window, null, surface) != @intFromEnum(vk.Result.success)) {
        return error.FailedToCreateWindowSurface;
    }
}

fn framebufferResizeCallback(window: glfw.Window, width: u32, height: u32) void {
    const vk_window = window.getUserPointer(Self) orelse unreachable;
    vk_window.width = width;
    vk_window.height = height;
}
