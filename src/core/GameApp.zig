const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const Allocator = std.mem.Allocator;

pub const GameApp = @This();

// fields
window: glfw.Window = undefined,
// end of fields

pub const StartupError = error{
    GLFWInit,
    WindowCreation,
};

pub const RunError = error{};

pub fn new() StartupError!GameApp {
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return StartupError.GLFWInit;
    }

    const window = glfw.Window.create(800, 600, "Yume", null, null, .{}) orelse {
        return StartupError.WindowCreation;
    };

    return .{ .window = window };
}

pub fn run(app: *GameApp) RunError!void {
    var now = std.time.milliTimestamp();
    while (!app.window.shouldClose()) {
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
