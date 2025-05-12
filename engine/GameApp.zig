const c = @import("clibs");

const std = @import("std");
const log = std.log.scoped(.GameApp);

const VulkanEngine = @import("VulkanEngine.zig");
pub const RenderCommand = VulkanEngine.RenderCommand;

const utils = @import("utils.zig");
const Uuid = @import("uuid.zig").Uuid;

const math3d = @import("math3d.zig");
const Vec2U = math3d.Vec2U;
const Vec3 = math3d.Vec3;

const Assets = @import("assets.zig").Assets;
const SceneAssetHandle = @import("assets.zig").SceneAssetHandle;

const Scene = @import("scene.zig").Scene;

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

components: std.StringHashMap(ecs.ComponentDef),

world: ecs.World,
scene_root: ecs.Entity,
scene: *Scene,
scene_handle: ?SceneAssetHandle = null,

delta: f32 = 0.016,

pub fn init(opts: struct {
    allocator: std.mem.Allocator,
    loader: assets.ResourceLoader,
    window_title: []const u8,
    window_extent: Vec2U,
}) *Self {
    utils.checkSdl(c.SDL_Init(c.SDL_INIT_VIDEO));

    const window = c.SDL_CreateWindow(
        opts.window_title.ptr,
        @intCast(opts.window_extent.x),
        @intCast(opts.window_extent.y),
        c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE,
    ) orelse @panic("Failed to create SDL window");

    _ = c.SDL_ShowWindow(window);

    const engine = VulkanEngine.init(opts.allocator, window);

    const self = opts.allocator.create(Self) catch @panic("OOM");

    self.* = Self{
        .world = ecs.World.init() catch @panic("failed to create the world"),
        .scene_root = undefined,
        .scene = Scene.init(opts.allocator) catch @panic("failed to create default scene"),
        .window_title = opts.window_title,
        .allocator = opts.allocator,
        .window = window,
        .inputs = inputs.init(window) catch @panic("Failed to initialize input manager"),
        .engine = engine,
        .components = std.StringHashMap(ecs.ComponentDef).init(opts.allocator),
    };

    self.scene_root = self.world.create("root");

    Assets.init(opts.allocator, &self.engine, opts.loader);

    self.registerComponent(ecs.components.Uuid);
    self.registerComponent(ecs.components.Meta);
    self.registerComponent(ecs.components.HierarchyOrder);

    self.registerComponent(ecs.components.LocalTransform);
    self.registerComponent(ecs.components.WorldTransform);

    self.registerComponent(ecs.components.Camera);
    self.registerComponent(ecs.components.DirectionalLight);
    self.registerComponent(ecs.components.PointLight);

    self.registerComponent(ecs.components.Mesh);
    self.registerComponent(ecs.components.Material);

    self.world.set(self.scene_root, ecs.components.WorldTransform, .{ .matrix = math3d.Mat4.IDENTITY });

    return self;
}

pub fn run(self: *Self, comptime Dispatcher: anytype) !void {
    var timer = try std.time.Timer.start();

    var quit = false;
    var event: c.SDL_Event = undefined;
    var d = Dispatcher.init(self);
    defer d.deinit();
    while (!quit) {
        self.newFrame();
        if (comptime std.meta.hasMethod(Dispatcher, "newFrame")) {
            d.newFrame();
        }
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_MOUSE_MOTION) {
                self.mouse.x = event.motion.x;
                self.mouse.y = event.motion.y;
            }
            if (comptime std.meta.hasMethod(Dispatcher, "processEvent")) {
                quit = !d.processEvent(&event);
            }
        }

        if (comptime std.meta.hasMethod(Dispatcher, "update")) {
            const cont: bool = try d.update();
            quit = quit or !cont;
        }
        if (comptime std.meta.hasMethod(Dispatcher, "draw")) {
            if ((c.SDL_GetWindowFlags(self.window) & c.SDL_WINDOW_MINIMIZED) == 0) {
                try d.draw();
            }
        }

        self.delta = @floatCast(@as(f64, @floatFromInt(timer.lap())) / 1_000_000_000.0);

        const TitleDelay = struct {
            var accumulator: f32 = 0.0;
        };

        TitleDelay.accumulator += self.delta;
        if (TitleDelay.accumulator > 0.1) {
            TitleDelay.accumulator = 0.0;
            const fps = 1.0 / self.delta;
            const title: ?[]u8 = if (comptime @hasDecl(Dispatcher, "windowTitle")) try d.windowTitle() else null;

            const new_title = try std.fmt.allocPrintZ(
                self.allocator,
                "{s} - FPS: {d:6.3}, ms: {d:6.3}",
                .{
                    title orelse self.window_title,
                    fps,
                    self.delta * 1000.0,
                },
            );
            defer self.allocator.free(new_title);
            _ = c.SDL_SetWindowTitle(self.window, new_title.ptr);
            if (title) |t| {
                self.allocator.free(t);
            }
        }
        if (comptime std.meta.hasMethod(Dispatcher, "endFrame")) {
            d.endFrame();
        }
    }
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

    self.world.deleteWith(ecs.pair(ecs.relations.ChildOf, self.scene_root));
    self.world.clear(self.scene_root);
    self.world.set(self.scene_root, ecs.components.WorldTransform, .{ .matrix = math3d.Mat4.IDENTITY, .dirty = true });

    var dfs = try self.scene.dfs();
    defer dfs.deinit();
    var entity_map = std.AutoHashMap(Uuid, ecs.Entity).init(self.allocator);
    defer entity_map.deinit();
    if (try dfs.next()) |root| {
        try entity_map.put(root.uuid, self.scene_root);
        self.world.setUuid(self.scene_root, root.uuid);
    }

    while (try dfs.next()) |decl| {
        const entity = self.world.create(null);

        try entity_map.put(decl.uuid, entity);

        log.debug("entity {s} {d}\n", .{ decl.name, entity });

        var idx: usize = 0;
        if (decl.parent) |parent| {
            idx = parent.findChildren(decl).?;
            const parent_entity = entity_map.get(parent.uuid).?;
            log.debug("entity {s} parent {d}\n", .{ decl.name, parent_entity });
            self.world.addPair(entity, ecs.relations.ChildOf, parent_entity);
        }

        _ = self.world.setMetaName(entity, decl.name);
        _ = self.world.setPathName(entity, if (decl.ident) |ident| ident else null);
        self.world.set(entity, ecs.components.Uuid, .{ .value = decl.uuid });
        // self.world.set(entity, ecs.components.Meta, .{ .allocator = @ptrCast(&self.allocator), .title = try self.allocator.dupeZ(u8, decl.name) });
        self.world.set(entity, ecs.components.HierarchyOrder, .{ .value = @intCast(idx) });

        var iter = decl.components.iterator();
        while (iter.next()) |it| {
            if (self.components.get(it.key_ptr.*)) |def| {
                if (def.deserialize) |de| {
                    self.world.addId(entity, def.id);
                    const ptr = c.ecs_get_mut_id(self.world.inner, entity, def.id).?;
                    if (!de(ptr, it.value_ptr, &self.allocator)) {
                        log.err("error: Failed to deserialize {s}.\n", .{it.key_ptr.*});
                        return error.FailedToLoadScene;
                    }
                } else {
                    log.err("error: Component {s} found but has no deserializer\n", .{it.key_ptr.*});
                    return error.FailedToLoadScene;
                }
            } else {
                log.err("error: Component {s} not found!\n", .{it.key_ptr.*});
                return error.FailedToLoadScene;
            }
        }
    }
}

pub fn snapshotLiveScene(self: *Self) !*Scene {
    if (self.scene_root == 0) {
        return error.SceneRootZero;
    }

    return try Scene.fromEcs(self.allocator, self.world, self.scene_root, self);
}

pub fn registerComponent(self: *Self, comptime T: type) void {
    const comp = self.world.component(T);
    self.components.put(ecs.typeName(T), comp) catch @panic("OOM");
}

pub fn registerTag(self: *Self, comptime T: type) void {
    self.world.tag(T);
}

pub fn isFocused(self: *const Self) bool {
    return c.SDL_GetWindowFlags(self.window) & c.SDL_WINDOW_INPUT_FOCUS != 0;
}

pub fn windowExtent(self: *const Self) Vec2U {
    return Vec2U.make(
        self.engine.swapchain_extent.width,
        self.engine.swapchain_extent.height,
    );
}

fn newFrame(self: *Self) void {
    self.inputs.clear();
}
