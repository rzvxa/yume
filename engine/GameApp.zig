const c = @import("clibs");

const std = @import("std");

const VulkanEngine = @import("VulkanEngine.zig");
pub const RenderCommand = VulkanEngine.RenderCommand;

const context = @import("context.zig");
pub const window_extent = context.window_extent;
const utils = @import("utils.zig");
const Uuid = @import("uuid.zig").Uuid;

const math3d = @import("math3d.zig");
const Vec3 = math3d.Vec3;

const Assets = @import("assets.zig").Assets;
const SceneAssetHandle = @import("assets.zig").SceneAssetHandle;

const Scene = @import("scene.zig").Scene;
const components = @import("components.zig");

const ecs = @import("ecs.zig");

const inputs = @import("inputs.zig");
const assets = @import("assets.zig");

const Self = @This();
mouse: c.ImVec2 = std.mem.zeroInit(c.ImVec2, .{}),

allocator: std.mem.Allocator = undefined,

window_title: []const u8,
window: *c.SDL_Window = undefined,

inputs: *inputs.InputContext,
engine: VulkanEngine,

components: std.StringHashMap(components.ComponentDef),

world: ecs.World,
scene_root: ecs.Entity,
scene: *Scene,
scene_handle: ?SceneAssetHandle = null,

delta: f32 = 0.016,

pub fn init(a: std.mem.Allocator, loader: assets.ResourceLoader, window_title: []const u8) *Self {
    utils.checkSdl(c.SDL_Init(c.SDL_INIT_VIDEO));

    const window = c.SDL_CreateWindow(window_title.ptr, window_extent.width, window_extent.height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE) orelse @panic("Failed to create SDL window");

    _ = c.SDL_ShowWindow(window);

    const engine = VulkanEngine.init(a, window);

    const self = a.create(Self) catch @panic("OOM");

    self.* = Self{
        .world = ecs.World.init() catch @panic("failed to create the world"),
        .scene_root = undefined,
        .scene = Scene.init(a) catch @panic("failed to create default scene"),
        .window_title = window_title,
        .allocator = a,
        .window = window,
        .inputs = inputs.init(window) catch @panic("Failed to initialize input manager"),
        .engine = engine,
        .components = std.StringHashMap(components.ComponentDef).init(a),
    };

    self.scene_root = self.world.create("root");

    Assets.init(a, &self.engine, loader);

    self.registerComponent(components.Uuid);
    self.registerComponent(components.Meta);
    self.registerComponent(components.HierarchyOrder);

    self.registerComponent(components.Position);
    self.registerComponent(components.Rotation);
    self.registerComponent(components.Scale);
    self.registerComponent(components.TransformMatrix);

    self.registerComponent(components.Camera);
    self.registerComponent(components.Mesh);
    self.registerComponent(components.Material);

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

        if (comptime std.meta.hasMethod(Dispatcher, "update")) {
            const cont: bool = d.update(self);
            quit = quit or !cont;
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
    if (self.scene_handle == null) {
        self.scene.deinit();
    }
    self.world.deinit();
    self.components.deinit();
    Assets.deinit();
    self.engine.deinit();
    self.allocator.destroy(self);
}

pub fn loadScene(self: *Self, scene_id: Uuid) !void {
    const old_handle = self.scene_handle;
    var old_scene = self.scene;
    self.scene_handle = try Assets.loadScene(scene_id);
    self.scene = try Assets.getScene(self.scene_handle.?);

    if (old_handle) |handle| {
        if (handle.uuid.raw != scene_id.raw) {
            try Assets.unload(handle.toAssetHandle());
        }
    } else {
        old_scene.deinit();
    }

    var dfs = try self.scene.dfs();
    defer dfs.deinit();
    var entity_map = std.AutoHashMap(Uuid, ecs.Entity).init(self.allocator);
    defer entity_map.deinit();
    self.world.clear(self.scene_root);
    if (try dfs.next()) |root| {
        try entity_map.put(root.uuid, self.scene_root);
    }

    while (try dfs.next()) |decl| {
        const entity = self.world.create(null);

        try entity_map.put(decl.uuid, entity);

        std.debug.print("entity {s} {d}\n", .{ decl.name, entity });

        var idx: usize = 0;
        if (decl.parent) |parent| {
            idx = parent.findChildren(decl).?;
            const parent_entity = entity_map.get(parent.uuid).?;
            std.debug.print("entity {s} parent {d}\n", .{ decl.name, parent_entity });
            self.world.addPair(entity, ecs.relations.ChildOf, parent_entity);
        }

        _ = self.world.setName(entity, decl.name);
        self.world.set(entity, components.Uuid, .{ .value = decl.uuid });
        // self.world.set(entity, components.Meta, .{ .allocator = @ptrCast(&self.allocator), .title = try self.allocator.dupeZ(u8, decl.name) });
        self.world.set(entity, components.HierarchyOrder, .{ .value = @intCast(idx) });

        var iter = decl.components.iterator();
        while (iter.next()) |it| {
            if (self.components.get(it.key_ptr.*)) |def| {
                if (def.deserialize) |de| {
                    self.world.addId(entity, def.id);
                    const ptr = c.ecs_get_mut_id(self.world.inner, entity, def.id).?;
                    if (!de(ptr, it.value_ptr, &self.allocator)) {
                        std.debug.print("error: Failed to deserialize {s}.\n", .{it.key_ptr.*});
                        return error.FailedToLoadScene;
                    }
                } else {
                    std.debug.print("error: Component {s} found but has no deserializer\n", .{it.key_ptr.*});
                    return error.FailedToLoadScene;
                }
            } else {
                std.debug.print("error: Component {s} not found!\n", .{it.key_ptr.*});
                return error.FailedToLoadScene;
            }
        }
    }
}

pub fn registerComponent(self: *Self, comptime T: type) void {
    const comp = self.world.component(T);
    self.components.put(ecs.typeName(T), comp) catch @panic("OOM");
}

fn newFrame(self: *Self) void {
    self.inputs.clear();
}
