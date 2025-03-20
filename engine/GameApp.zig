const c = @import("clibs");

const std = @import("std");

const VulkanEngine = @import("VulkanEngine.zig");
pub const RenderCommand = VulkanEngine.RenderCommand;

const context = @import("context.zig");
pub const window_extent = context.window_extent;
const utils = @import("utils.zig");
const Uuid = @import("uuid.zig");

const math3d = @import("math3d.zig");
const Vec3 = math3d.Vec3;

const AssetsDatabase = @import("assets.zig").AssetsDatabase;

const Scene = @import("scene.zig").Scene;
const Camera = @import("components/Camera.zig");

const inputs = @import("inputs.zig");
const assets = @import("assets.zig");

const Self = @This();
mouse: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),

allocator: std.mem.Allocator = undefined,

window_title: []const u8,
window: *c.SDL_Window = undefined,

inputs: *inputs.InputContext,
engine: VulkanEngine,

scene: *Scene,

delta: f32 = 0.016,

pub fn init(a: std.mem.Allocator, loader: assets.AssetLoader, window_title: []const u8) *Self {
    utils.checkSdl(c.SDL_Init(c.SDL_INIT_VIDEO));

    const window = c.SDL_CreateWindow(window_title.ptr, window_extent.width, window_extent.height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE) orelse @panic("Failed to create SDL window");

    _ = c.SDL_ShowWindow(window);

    const engine = VulkanEngine.init(a, window);

    const self = a.create(Self) catch @panic("OOM");

    self.* = Self{
        .scene = Scene.init(a) catch @panic("failed to create default scene"),
        .window_title = window_title,
        .allocator = a,
        .window = window,
        .inputs = inputs.init(window) catch @panic("Failed to initialize input manager"),
        .engine = engine,
    };

    assets.AssetsDatabase.init(a, &self.engine, loader);
    return self;
}

pub fn run(self: *Self, comptime Dispatcher: anytype) void {
    var timer = std.time.Timer.start() catch @panic("Failed to start timer");

    var quit = false;
    var event: c.SDL_Event = undefined;
    var d = Dispatcher.init(self);
    while (!quit) {
        self.newFrame();
        if (comptime std.meta.hasMethod(Dispatcher, "newFrame")) {
            d.newFrame(self);
        }
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_MOUSE_MOTION) {
                self.mouse.x = event.motion.x;
                self.mouse.y = event.motion.y;
            }
            if (comptime std.meta.hasMethod(Dispatcher, "processEvent")) {
                quit = !d.processEvent(self, &event);
            }
        }

        self.update();
        if (comptime std.meta.hasMethod(Dispatcher, "update")) {
            d.update(self);
        }
        if (comptime std.meta.hasMethod(Dispatcher, "draw")) {
            d.draw(self);
        }

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
        if (comptime std.meta.hasMethod(Dispatcher, "endFrame")) {
            d.endFrame(self);
        }
    }

    d.deinit(self);
}

pub fn deinit(self: *Self) void {
    // self.scene.deinit();
    assets.AssetsDatabase.deinit();
    self.engine.deinit();
    self.allocator.destroy(self);
}

pub fn loadScene(self: *Self, scene_id: Uuid) !void {
    const s = try AssetsDatabase.getOrLoadScene(scene_id);
    var old_scene = self.scene;
    self.scene = s;
    var iter = self.scene.dfs() catch @panic("OOM");
    defer iter.deinit();
    while (try iter.next()) |next| {
        if (next.getComponent(Camera)) |camera| {
            self.engine.main_camera = camera;
            break;
        }
        next.deref();
    }
    old_scene.deinit();
}

fn newFrame(self: *Self) void {
    self.inputs.clear();
}

fn update(self: *Self) void {
    var input: Vec3 = Vec3.make(0, 0, 0);
    input.z += if (self.inputs.isKeyDown(inputs.ScanCode.W)) 1 else 0;
    input.z += if (self.inputs.isKeyDown(inputs.ScanCode.S)) -1 else 0;
    input.x += if (self.inputs.isKeyDown(inputs.ScanCode.A)) -1 else 0;
    input.x += if (self.inputs.isKeyDown(inputs.ScanCode.D)) 1 else 0;
    input.y += if (self.inputs.isKeyDown(inputs.ScanCode.E)) 1 else 0;
    input.y += if (self.inputs.isKeyDown(inputs.ScanCode.Q)) -1 else 0;

    if (input.squaredLen() > (0.1 * 0.1)) {
        const camera_delta = input.normalized().mulf(self.delta * 5.0);
        var transform = &self.engine.main_camera.?.object.transform;
        transform.setPosition(transform.position().add(camera_delta));
    }
}
