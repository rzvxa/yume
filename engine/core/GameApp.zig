const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const ecs = @import("zig-ecs");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const rendering = @import("../rendering/mod.zig");

const backend = .{ .api = .vulkan, .max_frames_in_flight = 2 };

const Window = @import("../window/window.zig").Window(backend);
const RenderDevice = rendering.Device(backend);
const DescriptorPool = rendering.DescriptorPool(backend);
const GraphicBuffer = rendering.GraphicBuffer(backend);
const GlobalUbo = rendering.GlobalUbo;

pub const GameApp = @This();

// fields
arena: ArenaAllocator,
window: Window,
device: RenderDevice,

global_pool: DescriptorPool,

registry: ecs.Registry = undefined,
// end of fields

pub const StartupError = error{
    GLFWInit,
    RegistryInit,
    WindowCreation,
    RenderDeviceInit,
    UnsupportedPlatform,
    DescriptorPoolCreation,
};

pub const RunError = error{
    FailedToInitializeGlobalUbos,
};

pub inline fn init(title: [*:0]const u8) StartupError!GameApp {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    const registry = ecs.Registry.init(allocator);
    var window = Window.init(800, 600, title) catch |err| switch (err) {
        error.GLFWInit => return error.GLFWInit,
        error.WindowCreation => return error.WindowCreation,
        error.UnsupportedPlatform => return error.UnsupportedPlatform,
    };
    var device = RenderDevice.init(allocator, &window, .{ .enable_validation_layers = false }) catch return error.RenderDeviceInit;

    const global_pool = rendering.initDefaultDescriptorPool(backend, &device, allocator) catch return error.DescriptorPoolCreation;

    return .{
        .arena = arena,
        .window = window,
        .device = device,

        .global_pool = global_pool,

        .registry = registry,
    };
}

pub inline fn deinit(self: *GameApp) void {
    self.window.deinit();
    self.device.deinit();
    self.registry.deinit();
}

pub inline fn run(self: *GameApp) RunError!void {
    var ubo_buffers: [backend.max_frames_in_flight]GraphicBuffer = undefined;
    defer {
        for (0..ubo_buffers.len) |i| {
            ubo_buffers[i].deinit();
        }
    }
    for (0..ubo_buffers.len) |i| {
        ubo_buffers[i] = GraphicBuffer.init(
            &self.device,
            @sizeOf(GlobalUbo),
            1,
            .{ .uniform_buffer_bit = true },
            .{ .host_visible_bit = true },
            1,
        ) catch return error.FailedToInitializeGlobalUbos;
        ubo_buffers[i].map(.{}) catch return error.FailedToInitializeGlobalUbos;
    }
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
