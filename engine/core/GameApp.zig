const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Window = @import("../window/Window.zig");
const renderer = @import("../rendering/vulkan/renderer.zig");
const GraphicsContext = @import("../rendering/vulkan/graphics_context.zig").GraphicsContext;
const Mesh = @import("../rendering/Mesh.zig");
const Vertex = @import("../rendering/Vertex.zig");
const Vec3 = @import("../root.zig").Vec3;
const Vec2 = @import("../root.zig").Vec2;

pub const StartupError = error{
    GLFWInit,
    WindowCreation,
    RendererInit,
    UnsupportedPlatform,
    OutOfMemory,
};

pub const RunError = error{
    Unknown,
    OutOfMemory,
};

pub fn GameApp(comptime Dispatcher: type) type {
    return struct {
        pub const Self = @This();
        pub const Renderer = renderer.Renderer();

        arena: ArenaAllocator,
        window: Window,
        renderer: *Renderer,

        pub inline fn init(title: [*:0]const u8) StartupError!*Self {
            var arena = ArenaAllocator.init(std.heap.page_allocator);
            const allocator = arena.allocator();
            var self = try allocator.create(Self);

            const window = Window.init(800, 600, title) catch |err| switch (err) {
                error.GLFWInit => return error.GLFWInit,
                error.WindowCreation => return error.WindowCreation,
                error.UnsupportedPlatform => return error.UnsupportedPlatform,
            };
            self.* = .{
                .arena = arena,

                .window = window,
                .renderer = Renderer.init(&self.window, allocator) catch return error.RendererInit,
            };
            return self;
        }

        pub inline fn deinit(self: *Self) void {
            self.renderer.deinit();
            self.window.deinit();
        }

        pub inline fn run(self: *Self) RunError!void {
            var now = std.time.nanoTimestamp();
            var triangle = Mesh.init(self.renderer, &.{
                .{
                    .position = Vec3.new(0, -0.5, 0),
                    .color = Vec3.new(1, 0, 0),
                    .normal = Vec3.as(0),
                    .uv = Vec2.as(0),
                },
                .{
                    .position = Vec3.new(0.5, 0.5, 0),
                    .color = Vec3.new(0, 1, 0),
                    .normal = Vec3.as(0),
                    .uv = Vec2.as(0),
                },
                .{
                    .position = Vec3.new(-0.5, 0.5, 0),
                    .color = Vec3.new(0, 0, 1),
                    .normal = Vec3.as(0),
                    .uv = Vec2.as(0),
                },
            }, &.{}) catch return error.Unknown;
            defer triangle.deinit();
            while (!self.window.shouldClose()) {
                const size = self.window.getFramebufferSize();

                // Don't present or resize swapchain while the window is minimized
                if (size.width == 0 or size.height == 0) {
                    glfw.pollEvents();
                    continue;
                }

                const dt = dt: {
                    const new_time = std.time.nanoTimestamp();
                    const delta: f32 = @as(f32, @floatFromInt(new_time - now)) / 1e9;
                    now = new_time;
                    break :dt delta;
                };

                self.update(dt);
                self.renderer.render(size, &triangle) catch return error.Unknown;
            }
            self.renderer.swapchain.waitForAllFences() catch return error.Unknown;
            self.renderer.gctx.dev.deviceWaitIdle() catch return error.Unknown;
        }

        fn update(self: *Self, dt: f32) void {
            _ = self;
            switch (comptime @typeInfo(Dispatcher)) {
                .Struct => |struct_| {
                    inline for (struct_.decls) |decl| {
                        if (comptime std.mem.eql(u8, decl.name, "update")) {
                            Dispatcher.update(dt);
                        }
                    }
                },
                else => @compileError("expected a struct type as `dispatcher`"),
            }
        }
    };
}
