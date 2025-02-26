const c = @import("clibs");

const std = @import("std");

const VulkanEngine = @import("VulkanEngine.zig");
pub const RenderCommand = VulkanEngine.RenderCommand;

const context = @import("context.zig");
pub const window_extent = context.window_extent;
const utils = @import("utils.zig");

const math3d = @import("math3d.zig");
const Vec3 = math3d.Vec3;

const Self = @This();
mouse: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),

allocator: std.mem.Allocator = undefined,

window_title: []const u8,
window: *c.SDL_Window = undefined,

engine: VulkanEngine,

delta: f32 = 0.016,

pub fn init(a: std.mem.Allocator, window_title: []const u8) Self {
    utils.checkSdl(c.SDL_Init(c.SDL_INIT_VIDEO));

    const window = c.SDL_CreateWindow(window_title.ptr, window_extent.width, window_extent.height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE) orelse @panic("Failed to create SDL window");

    _ = c.SDL_ShowWindow(window);

    const engine = VulkanEngine.init(a, window);

    return .{
        .window_title = window_title,
        .allocator = a,
        .window = window,
        .engine = engine,
    };
}

pub fn run(self: *Self, comptime dispatcher: anytype) void {
    var timer = std.time.Timer.start() catch @panic("Failed to start timer");

    var quit = false;
    var event: c.SDL_Event = undefined;
    var d = dispatcher.init(self);
    while (!quit) {
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.type == c.SDL_EVENT_MOUSE_MOTION) {
                self.mouse.x = event.motion.x;
                self.mouse.y = event.motion.y;
            }
            quit = !d.processEvent(self, &event);
        }

        if (self.engine.camera_input.squaredLen() > (0.1 * 0.1)) {
            const camera_delta = self.engine.camera_input.normalized().mulf(self.delta * 5.0);
            self.engine.camera_pos = Vec3.add(self.engine.camera_pos, camera_delta);
        }

        d.update(self);
        d.draw(self);

        self.delta = @floatCast(@as(f64, @floatFromInt(timer.lap())) / 1_000_000_000.0);

        const TitleDelay = struct {
            var accumulator: f32 = 0.0;
        };

        TitleDelay.accumulator += self.delta;
        if (TitleDelay.accumulator > 0.1) {
            TitleDelay.accumulator = 0.0;
            const fps = 1.0 / self.delta;
            const new_title = std.fmt.allocPrintZ(
                self.allocator,
                "{s} - FPS: {d:6.3}, ms: {d:6.3}",
                .{ self.window_title, fps, self.delta * 1000.0 },
            ) catch @panic("Out of memory");
            defer self.allocator.free(new_title);
            _ = c.SDL_SetWindowTitle(self.window, new_title.ptr);
        }
    }

    d.deinit(self);
}

pub fn deinit(self: *Self) void {
    self.engine.deinit();
}
