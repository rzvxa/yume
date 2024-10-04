const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const ecs = @import("zig-ecs");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Window = @import("../window/window.zig").Window(.Vulkan);
const RenderDevice = @import("../rendering/device.zig").Device(.Vulkan);

pub const GameApp = @This();

// fields
arena: ArenaAllocator,
window: Window,
device: RenderDevice,
registry: ecs.Registry = undefined,
// end of fields

pub const StartupError = error{
    GLFWInit,
    RegistryInit,
    WindowCreation,
    RenderDeviceInit,
    UnsupportedPlatform,
};

pub const RunError = error{};

pub inline fn init(title: [*:0]const u8) StartupError!GameApp {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    const registry = ecs.Registry.init(allocator);
    var window = Window.init(800, 600, title) catch |err| switch (err) {
        error.GLFWInit => return error.GLFWInit,
        error.WindowCreation => return error.WindowCreation,
        error.UnsupportedPlatform => return error.UnsupportedPlatform,
    };
    const device = RenderDevice.init(allocator, &window, .{ .enable_validation_layers = false }) catch return error.RenderDeviceInit;

    return .{
        .arena = arena,
        .window = window,
        .device = device,
        .registry = registry,
    };
}

pub inline fn deinit(self: *GameApp) void {
    self.window.deinit();
    self.registry.deinit();
}

pub inline fn run(self: *GameApp) RunError!void {
    var now = std.time.milliTimestamp();
    while (!self.window.shouldClose()) {
        glfw.pollEvents();
        const delta_time = dt: {
            const new_time = std.time.milliTimestamp();
            const delta = new_time - now;
            now = new_time;
            break :dt delta;
        };

        _ = delta_time;
    }
}
