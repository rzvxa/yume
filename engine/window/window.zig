pub fn Window(comptime backend: WindowBackend) type {
    return switch (backend) {
        .Vulkan => {
            return @import("vulkan/VulkanWindow.zig");
        },
    };
}

pub const WindowBackend = enum { Vulkan };
