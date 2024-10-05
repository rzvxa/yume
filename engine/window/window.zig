const RenderBackend = @import("../rendering/mod.zig").RenderBackend;
pub fn Window(comptime backend: RenderBackend) type {
    return switch (backend.api) {
        .vulkan => {
            return @import("vulkan/VulkanWindow.zig");
        },
    };
}
