const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");

const ecs = @import("coyote-ecs");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const rendering = @import("../rendering/mod.zig");
const Mesh = @import("../rendering/Mesh.zig");

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
const FrameInfo = rendering.FrameInfo;

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

world: *ecs.World,
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

        .world = ecs.World.create() catch return error.RegistryInit,
    };
}

pub inline fn deinit(self: *GameApp) void {
    self.window.deinit();
    self.global_pool.deinit();
    self.renderer.deinit();
    self.device.deinit();
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

    // const Camera = self.world.components.create(components.Camera) catch return error.Unknown;
    // const Position = self.world.components.create(components.Position) catch return error.Unknown;
    // const Rotation = self.world.components.create(components.Rotation) catch return error.Unknown;
    // const MeshComp = self.world.components.create(components.MeshComp) catch return error.Unknown;
    const T = struct {
        mesh: Mesh,
        pos: Vec3,
        rot: Vec3,
    };
    var cube: T = .{
        .pos = Vec3.new(0, 0, 0),
        .rot = Vec3.as(0),
        .mesh = Mesh.fromFile("assets/models/cube.obj", &self.device, allocator) catch return error.Unknown,
    };

    // var cube = self.world.entities.create() catch return error.Unknown;
    // cube.attach(Position, components.Position{ .inner = Vec3.as(0) }) catch return error.Unknown;
    // cube.attach(Rotation, components.Rotation{ .inner = Vec3.as(0) }) catch return error.Unknown;
    // cube.attach(MeshComp, components.MeshComp{ .inner = cube_mesh }) catch return error.Unknown;

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
        writer.flush(&global_descriptor_sets[i]) catch return error.Unknown;
    }

    const render_pipeline = SimpleRenderPipeline.init(
        &self.device,
        self.renderer.swapchain.render_pass,
        global_set_layout.descriptor_set_layout,
        allocator,
    ) catch return error.Unknown;

    var camera: struct {
        cam: components.Camera,
        pos: Vec3,
        rot: Vec3,
    } = .{
        .cam = components.Camera{},
        .pos = Vec3.new(0, 0, -2.5),
        .rot = Vec3.as(0),
    };
    // var camera = self.world.entities.create() catch return error.Unknown;
    {
        // var cam = components.Camera{};
        camera.cam.setViewTarget(camera.pos, cube.pos, Vec3.up);
        // camera.attach(Camera, cam) catch return error.Unknown;
        // camera.attach(Position, components.Position{ .inner = Vec3.new(0, 0, -2.5) }) catch return error.Unknown;
        // camera.attach(Rotation, components.Rotation{ .inner = Vec3.as(0) }) catch return error.Unknown;
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

        // var camera_iter = self.world.entities.iteratorFilter(components.Camera);

        const aspect_ratio = self.renderer.aspectRatio();
        // while (camera_iter.next()) |entity| {
        // const pos = ecs.Cast(components.Position, entity.getOneComponent(components.Position));
        // const rot = ecs.Cast(components.Rotation, entity.getOneComponent(components.Rotation));
        // var cam = ecs.Cast(components.Camera, entity.getOneComponent(components.Camera));

        camera.cam.setViewYXZ(camera.pos, camera.rot);
        camera.cam.setPrespectiveProjection(math.trigonometric.radians(360.0), aspect_ratio, 0.01, 10);
        const command_buffer = (self.renderer.beginFrame() catch return error.Unknown) orelse return error.Unknown;
        if (command_buffer == .null_handle) {
            continue;
        }
        const frame_index = self.renderer.current_frame_index;
        const frame_info = FrameInfo{
            .index = frame_index,
            .time = delta_time,
            .command_buffer = command_buffer,
            .camera = &camera.cam,
            .global_descriptor_set = global_descriptor_sets[frame_index],
        };

        // update
        var ubo = GlobalUbo{};
        ubo.projection = camera.cam.projection_matrix;
        ubo.view = camera.cam.view_matrix;
        ubo_buffers[frame_index].writeToBuffer(.{ .data = &ubo });
        ubo_buffers[frame_index].flush(.{}) catch return error.Unknown;

        // render
        self.renderer.beginSwapchainRenderPass(command_buffer);
        render_pipeline.render(&frame_info, T, &cube);
        self.renderer.endSwapchainRenderPass(command_buffer);

        self.renderer.endFrame() catch return error.Unknown;
    }
    // }
    self.device.device.deviceWaitIdle() catch return error.Unknown;
}
