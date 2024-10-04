pub fn Device(comptime backend: RenderBackend) type {
    return switch (backend) {
        .Vulkan => {
            return @import("vulkan/VulkanDevice.zig");
        },
    };
}

pub const RenderBackend = enum { Vulkan };
