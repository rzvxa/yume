const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const ecs = @import("ecs.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const GameApp = @This();

// fields
arena: ArenaAllocator,
window: glfw.Window = undefined,
registry: ecs.Registry = undefined,
// end of fields

pub const StartupError = error{
    GLFWInit,
    RegistryInit,
    WindowCreation,
};

pub const RunError = error{};

pub inline fn init() StartupError!GameApp {
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return StartupError.GLFWInit;
    }

    const window = glfw.Window.create(800, 600, "Yume", null, null, .{}) orelse {
        return StartupError.WindowCreation;
    };

    var arena = ArenaAllocator.init(std.heap.page_allocator);
    var registry = ecs.Registry.init(arena.allocator()) catch return StartupError.RegistryInit;
    const entity = registry.newEntity();
    registry.addComponent(entity, struct { x: f32, y: f32 }, .{ .x = 123, .y = 456 }) catch unreachable;

    return .{ .arena = arena, .window = window, .registry = registry };
}

pub inline fn deinit(self: GameApp) void {
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
