const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const renderer = @import("../rendering/vulkan/renderer.zig");

pub const GameApp = @This();

// fields
arena: ArenaAllocator,
// end of fields

pub const StartupError = error{
    GLFWInit,
    RegistryInit,
    WindowCreation,
    RenderDeviceInit,
    RendererInit,
    UnsupportedPlatform,
    DescriptorPoolCreation,
};

pub const RunError = error{
    Unknown,
    FailedToInitializeGlobalUbos,
    FailedToInitializeDescriptorSetLayout,
    OutOfMemory,
};

pub inline fn init(title: [*:0]const u8) StartupError!GameApp {
    const arena = ArenaAllocator.init(std.heap.page_allocator);
    //     const allocator = arena.allocator();
    //     var window = Window.init(800, 600, title) catch |err| switch (err) {
    //         error.GLFWInit => return error.GLFWInit,
    //         error.WindowCreation => return error.WindowCreation,
    //         error.UnsupportedPlatform => return error.UnsupportedPlatform,
    //     };
    //     var device = GraphicsContext.init(allocator, &window, .{ .enable_validation_layers = true }) catch return error.RenderDeviceInit;
    //
    //
    //     const global_pool = rendering.initDefaultDescriptorPool(backend, &device, allocator) catch return error.DescriptorPoolCreation;
    //
    _ = title;
    return .{
        // .title = title,
        .arena = arena,
        //
        //         .window = window,
        //         .device = device,
        //         .renderer = renderer,
        //
        //         .global_pool = global_pool,
        //
        //         .world = ecs.World.create() catch return error.RegistryInit,
    };
}

pub inline fn deinit(self: *GameApp) void {
    _ = self;
    //     self.window.deinit();
    //     self.global_pool.deinit();
    //     self.renderer.deinit();
    //     self.device.deinit();
}

pub inline fn run(self: *GameApp, comptime dispatcher: type) RunError!void {
    _ = self;
    _ = dispatcher;
    renderer.triangle() catch return error.Unknown;
}
