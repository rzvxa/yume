const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const ecs = @import("ecs.zig");

const Allocator = std.mem.Allocator;

pub const GameApp = @This();

// fields
window: glfw.Window = undefined,
registry: ecs.Registry = undefined,
// end of fields

pub const StartupError = error{
    GLFWInit,
    RegistryInit,
    WindowCreation,
};

pub const RunError = error{};

pub inline fn create() StartupError!GameApp {
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return StartupError.GLFWInit;
    }

    const window = glfw.Window.create(800, 600, "Yume", null, null, .{}) orelse {
        return StartupError.WindowCreation;
    };

    var registry = ecs.Registry.init() catch return StartupError.RegistryInit;
    const entity = registry.newEntity();
    registry.addComponent(entity, .{ .x = 123, .y = 456 }) catch unreachable;

    return .{ .window = window, .registry = registry };
}

pub inline fn destroy(self: GameApp) void {
    self.window.destroy();
    self.registry.deinit();
}

pub inline fn run(self: GameApp) RunError!void {
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
