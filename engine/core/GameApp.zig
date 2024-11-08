const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const ecs = @import("zig-ecs");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const rendering = @import("../rendering/mod.zig");

const backend = @import("../constants.zig").backend;

const Window = @import("../window/window.zig").Window(backend);
const RenderDevice = rendering.Device(backend);
const SimpleRenderPipeline = rendering.SimpleRenderPipeline;
const DescriptorPool = rendering.DescriptorPool(backend);
const DescriptorSetLayout = rendering.DescriptorSetLayout(backend);
const DescriptorSet = rendering.DescriptorSet;
const DescriptorWriter = rendering.DescriptorWriter(backend);
const GraphicBuffer = rendering.GraphicBuffer(backend);
const Renderer = rendering.Renderer(backend);
const GlobalUbo = rendering.GlobalUbo;

const math = @import("../root.zig").math;
const Vec3 = @import("../root.zig").Vec3;
const components = @import("../components/mod.zig");

pub const GameApp = @This();

// fields
arena: ArenaAllocator,

window: Window,
device: RenderDevice,
renderer: Renderer,

global_pool: DescriptorPool,

registry: ecs.Registry = undefined,
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
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    const registry = ecs.Registry.init(allocator);
    var window = Window.init(800, 600, title) catch |err| switch (err) {
        error.GLFWInit => return error.GLFWInit,
        error.WindowCreation => return error.WindowCreation,
        error.UnsupportedPlatform => return error.UnsupportedPlatform,
    };
    var device = RenderDevice.init(allocator, &window, .{ .enable_validation_layers = true }) catch return error.RenderDeviceInit;

    const renderer = Renderer.init(&device, &window, allocator) catch return error.RendererInit;

    const global_pool = rendering.initDefaultDescriptorPool(backend, &device, allocator) catch return error.DescriptorPoolCreation;

    return .{
        .arena = arena,

        .window = window,
        .device = device,
        .renderer = renderer,

        .global_pool = global_pool,

        .registry = registry,
    };
}

pub inline fn deinit(self: *GameApp) void {
    self.window.deinit();
    self.global_pool.deinit();
    self.renderer.deinit();
    self.device.deinit();
    // TODO: this crashes!
    // self.registry.deinit();
}

pub inline fn run(self: *GameApp, comptime dispatcher: type) RunError!void {
    const allocator = self.arena.allocator();
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

    var bindings = allocator.alloc(DescriptorSetLayout.BindingOptions, 1) catch return error.OutOfMemory;
    bindings[0] = .{
        .binding = 0,
        .type = .uniform_buffer,
        .stage_flags = .{ .vertex_bit = true, .fragment_bit = true },
    };
    defer allocator.free(bindings);

    var global_set_layout = DescriptorSetLayout.init(&self.device, bindings, allocator) catch return error.FailedToInitializeDescriptorSetLayout;
    defer global_set_layout.deinit();

    const global_descriptor_sets = allocator.alloc(DescriptorSet, backend.max_frames_in_flight) catch return error.OutOfMemory;
    defer allocator.free(global_descriptor_sets);

    for (0..global_descriptor_sets.len) |i| {
        var buffer_info = ubo_buffers[i].descriptorInfo(.{});
        var writer = try DescriptorWriter.init(&global_set_layout, &self.global_pool, allocator);
        defer writer.deinit();
        try writer.writeBuffer(0, &buffer_info);
        writer.flush(global_descriptor_sets[i]) catch return error.Unknown;
    }

    const render_pipeline = SimpleRenderPipeline.init(
        &self.device,
        self.renderer.swapchain.render_pass,
        global_set_layout.descriptor_set_layout,
        allocator,
    ) catch return error.Unknown;
    _ = render_pipeline;

    const registry = &self.registry;
    var camera_view = registry.view(.{ components.Position, components.Rotation, components.Camera }, .{});
    {
        const main_camera = registry.create();
        registry.add(main_camera, components.Position{ .inner = Vec3.new(0, 0, -2.5) });
        registry.add(main_camera, components.Rotation{ .inner = Vec3.as(0) });
        registry.add(main_camera, comp: {
            var camera = components.Camera{};
            camera.setViewTarget(Vec3.new(-1, -2, 2), Vec3.new(0, 0, 2.5), Vec3.up);
            break :comp camera;
        });
    }

    var now = std.time.nanoTimestamp();
    while (!self.window.shouldClose()) {
        glfw.pollEvents();
        const delta_time = dt: {
            const new_time = std.time.nanoTimestamp();
            const delta: f32 = @as(f32, @floatFromInt(new_time - now)) / 1e9;
            now = new_time;
            break :dt delta;
        };

        switch (comptime @typeInfo(dispatcher)) {
            .Struct => |struct_| {
                inline for (struct_.decls) |decl| {
                    if (comptime std.mem.eql(u8, decl.name, "update")) {
                        dispatcher.update(delta_time);
                    }
                }
            },
            else => @compileError("expected a struct type as `dispatcher`"),
        }

        var camera_iter = camera_view.entityIterator();

        const aspect_ratio = self.renderer.aspectRatio();
        while (camera_iter.next()) |entity| {
            const pos = camera_view.getConst(components.Position, entity);
            const rot = camera_view.getConst(components.Rotation, entity);
            const cam = camera_view.get(components.Camera, entity);

            cam.setViewYXZ(pos.inner, rot.inner);
            cam.setPrespectiveProjection(math.trigonometric.radians(50.0), aspect_ratio, 0.01, 10);
        }
    }
    self.device.device.deviceWaitIdle() catch return error.Unknown;
}
