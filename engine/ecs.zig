const c = @import("clibs");
const std = @import("std");
const log = std.log.scoped(.ecs);

const Mat4 = @import("math3d.zig").Mat4;
const GameApp = @import("GameApp.zig");
const Uuid = @import("uuid.zig").Uuid;
const assets = @import("assets.zig");
const Dynamic = @import("serialization/dynamic.zig").Dynamic;

pub const TypeId = c.ecs_id_t;
pub const Entity = c.ecs_entity_t;
pub const QueryDesc = c.ecs_query_desc_t;

pub const Query = extern struct {
    const Self = @This();
    inner: c.ecs_query_t,

    inline fn from(raw: *c.ecs_query_t) *Query {
        return @ptrCast(raw);
    }

    pub inline fn deinit(self: *Self) void {
        c.ecs_query_fini(self.castMut());
    }

    pub inline fn iter(self: *const Self) Iterator {
        return Iterator{ .inner = c.ecs_query_iter(self.inner.world orelse self.inner.real_world.?, self.cast()) };
    }

    pub inline fn cast(self: *const Self) *const c.ecs_query_t {
        return @ptrCast(self);
    }

    pub inline fn castMut(self: *Self) *c.ecs_query_t {
        return @ptrCast(self);
    }

    pub inline fn isTrue(self: *const Self) bool {
        return c.ecs_query_is_true(self.cast());
    }
};

pub const Iterator = extern struct {
    const Self = @This();
    inner: c.ecs_iter_t,

    pub inline fn from(raw: *c.ecs_iter_t) *Iterator {
        return @ptrCast(raw);
    }

    pub inline fn deinit(self: *Self) void {
        c.ecs_iter_fini(self.castMut());
    }

    pub inline fn next(self: *Self) bool {
        return c.ecs_iter_next(self.castMut());
    }

    pub inline fn changed(self: *Self) bool {
        return c.ecs_iter_changed(self.castMut());
    }

    pub inline fn cast(self: *const Self) *const c.ecs_iter_t {
        return @ptrCast(self);
    }

    pub inline fn castMut(self: *Self) *c.ecs_iter_t {
        return @ptrCast(self);
    }

    pub inline fn world(self: *Self) World {
        return World{ .inner = self.inner.world.? };
    }

    pub inline fn realWorld(self: *Self) World {
        return World{ .inner = self.inner.real_world.? };
    }
};

pub const World = struct {
    const Self = @This();

    inner: *c.ecs_world_t,

    pub fn init() !Self {
        staticEsqueInitializer();
        const inner = c.ecs_init();
        if (inner == null) {
            return error.FailedToInitializeEcsWorld;
        }
        return .{ .inner = inner.? };
    }

    pub fn deinit(self: Self) void {
        std.debug.assert(c.ecs_fini(self.inner) == 0);
    }

    pub fn tag(self: Self, comptime T: type) void {
        if (@sizeOf(T) != 0) {
            @compileError("For registering non-zero-sized components use `component` instead");
        }

        const meta = Reflect(T);
        std.debug.assert(meta.id == 0);

        meta.id = c.ecs_entity_init(self.inner, &.{ .name = typeName(T) });
    }

    pub fn component(self: Self, comptime T: type) ComponentDef {
        if (@sizeOf(T) == 0) {
            @compileError("For registering zero-sized components use `tag` instead");
        }

        if (@typeInfo(T) != .Struct) {
            @compileError("ECS componenets must be a struct instead got " ++ @typeName(T));
        }

        const meta = Reflect(T);
        std.debug.assert(meta.id == 0);

        meta.id = mkp_component_init(self.inner, &.{
            .entity = c.ecs_entity_init(self.inner, &.{
                .use_low_id = true,
                .name = typeName(T),
                .symbol = typeName(T),
            }),
            .type = .{
                .size = @sizeOf(T),
                .alignment = @alignOf(T),
                .hooks = .{
                    .dtor = switch (@typeInfo(T)) {
                        .Struct => if (@hasDecl(T, "deinit")) struct {
                            pub fn f(ptr: ?*anyopaque, count: i32, _: [*c]const TypeInfo) callconv(.C) void {
                                var c_ptr = @as([*c]T, @ptrCast(@alignCast(ptr)));
                                var span = c_ptr[0..@intCast(count)];
                                for (0..span.len) |i| T.deinit(&span[i]);
                            }
                        }.f else null,
                        else => null,
                    },

                    .on_add = switch (@typeInfo(T)) {
                        .Struct => if (@hasDecl(T, "onAdd")) struct {
                            pub fn f(iter: [*c]c.ecs_iter_t) callconv(.C) void {
                                T.onAdd(Iterator.from(iter));
                            }
                        }.f else null,
                        else => null,
                    },
                    .on_set = switch (@typeInfo(T)) {
                        .Struct => if (@hasDecl(T, "onSet")) struct {
                            pub fn f(iter: [*c]c.ecs_iter_t) callconv(.C) void {
                                T.onSet(Iterator.from(iter));
                            }
                        }.f else null,
                        else => null,
                    },
                    .on_remove = switch (@typeInfo(T)) {
                        .Struct => if (@hasDecl(T, "onRemove")) struct {
                            pub fn f(iter: [*c]c.ecs_iter_t) callconv(.C) void {
                                T.onRemove(Iterator.from(iter));
                            }
                        }.f else null,
                        else => null,
                    },
                },
            },
        });

        std.debug.assert(meta.id != 0);
        return .{
            .id = meta.id,
            .icon = switch (@typeInfo(T)) {
                .Struct => if (@hasDecl(T, "editorIcon")) T.editorIcon() else null,
                else => null,
            },
            .billboard = switch (@typeInfo(T)) {
                .Struct => if (@hasDecl(T, "editorBillboard")) T.editorBillboard() else null,
                else => null,
            },
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
            .default = if (@hasDecl(T, "default")) struct {
                pub fn f(ptr: *anyopaque, ent: Entity, ctx: *GameApp, resolver: ResourceResolver) callconv(.C) bool {
                    const params = @typeInfo(@TypeOf(T.default)).Fn.params;
                    if (params[params.len - 1].type == ResourceResolver) {
                        return T.default(@ptrCast(@alignCast(ptr)), ent, ctx, resolver);
                    } else {
                        return T.default(@ptrCast(@alignCast(ptr)), ent, ctx);
                    }
                }
            }.f else null,
            .serialize = if (@hasDecl(T, "serialize")) struct {
                pub fn f(ptr: *const anyopaque, allocator: *const std.mem.Allocator) callconv(.C) SerializationResult {
                    const result = T.serialize(@ptrCast(@alignCast(ptr)), allocator.*) catch |err| {
                        log.err("serialization encountered an error, {}", .{err});
                        return .{ .ok = false };
                    };
                    return .{ .ok = true, .result = result };
                }
            }.f else if (@hasDecl(T, "serialize"))
                @compileError("ECS componenet '" ++ @typeName(T) ++ "' has a `serialize` method doesn't provide a `deserialize` method declaration")
            else
                null,
            .deserialize = if (@hasDecl(T, "deserialize")) blk: {
                if (!@hasDecl(T, "serialize")) {
                    log.warn("ECS componenet '" ++ @typeName(T) ++ "' has a `deserialize` method but doesn't provide a `serialize` method declaration.\n", .{});
                }
                break :blk struct {
                    pub fn f(ptr: *anyopaque, value: *const Dynamic, allocator: *const std.mem.Allocator) callconv(.C) bool {
                        T.deserialize(@ptrCast(@alignCast(ptr)), value, allocator.*) catch |err| {
                            log.err("deserialization encountered an error, {}", .{err});
                            return false;
                        };
                        return true;
                    }
                }.f;
            } else if (@hasDecl(T, "serialize"))
                @compileError("ECS componenet '" ++ @typeName(T) ++ "' has a `serialize` method doesn't provide a `deserialize` method declaration")
            else
                null,
        };
    }

    pub fn autoFunctionTerms(comptime func: anytype) [32]c.ecs_term_t {
        var terms = std.mem.zeroes([32]c.ecs_term_t);
        const fn_type = @typeInfo(@TypeOf(func)).Fn;
        const has_it_param = comptime hasItParam(fn_type.params);
        const start_index = if (has_it_param) 1 else 0;
        inline for (start_index..fn_type.params.len) |i| {
            const p = fn_type.params[i];
            const param_type_info = @typeInfo(p.type.?).Pointer;
            const inout: InOut = if (param_type_info.is_const) .in else .in_out;
            terms[i - start_index] = .{ .id = typeId(param_type_info.child), .inout = inout.cast() };
        }
        return terms;
    }

    pub fn autoSystemFnDesc(comptime fn_system: anytype) SystemDesc {
        return systemFnDesc(fn_system, autoFunctionTerms(fn_system));
    }

    pub fn systemFnDesc(comptime fn_system: anytype, terms: [32]c.ecs_term_t) SystemDesc {
        const system_struct = SystemImpl(fn_system);

        var system_desc = SystemDesc{};
        system_desc.callback = @ptrCast(&system_struct.exec);
        system_desc.query.terms = terms;

        return system_desc;
    }

    pub fn systemFn(
        self: Self,
        name: [*:0]const u8,
        phase: Entity,
        comptime fn_system: anytype,
    ) Entity {
        var desc = autoSystemFnDesc(fn_system);
        return self.system(name, phase, &desc);
    }

    pub fn system(
        self: Self,
        name: [*:0]const u8,
        phase: Entity,
        system_desc: *const SystemDesc,
    ) Entity {
        var entity_desc = c.ecs_entity_desc_t{};
        entity_desc.id = c.ecs_new(self.inner);
        entity_desc.name = name;
        const first = if (phase != 0) pair(relations.DependsOn, phase) else 0;
        const second = phase;
        entity_desc.add = &[_]c.ecs_id_t{ first, second, 0 };

        var desc = system_desc.*;
        desc.entity = self.createEx(&entity_desc);
        return self.systemEx(&desc);
    }

    pub inline fn systemEx(self: Self, desc: *const SystemDesc) Entity {
        return mkp_system_init(self.inner, desc);
    }

    pub fn observerFn(
        self: Self,
        name: [*:0]const u8,
        // events: [8]Event,
        comptime fn_observer: anytype,
    ) Entity {
        var desc = autoSystemFnDesc(fn_observer);
        return self.system(name, 0, &desc);
    }

    pub fn observer(
        self: Self,
        name: [*:0]const u8,
        events: [8]Event,
        system_desc: *c.ecs_system_desc_t,
    ) Entity {
        var entity_desc = c.ecs_entity_desc_t{};
        entity_desc.id = c.ecs_new(self.inner);
        entity_desc.name = name;
        _ = events;

        system_desc.entity = self.createEx(&entity_desc);
        return c.ecs_system_init(self.inner, system_desc);
    }

    pub inline fn observerEx(self: Self, o: *const ObserverDesc) Entity {
        return c.ecs_observer_init(self.inner, @ptrCast(o));
    }

    pub inline fn entity(self: Self, opts: struct {
        uuid: ?Uuid = null,
        name: [*:0]const u8 = "New Entity",
        ident: ?[*:0]const u8 = null,
        parent: ?Entity = null,
        transform: ?components.LocalTransform = null,
    }) Entity {
        const ent = self.create(opts.ident);
        if (opts.parent) |parent| {
            self.addPair(ent, relations.ChildOf, parent);
        }
        self.set(ent, components.Meta, components.Meta.init(opts.name) catch @panic("Failed to create meta"));
        self.set(ent, components.Uuid, .{ .value = opts.uuid orelse Uuid.new() });
        self.set(ent, components.LocalTransform, opts.transform orelse components.LocalTransform{ .matrix = Mat4.IDENTITY });
        return ent;
    }

    pub inline fn create(self: Self, ident: ?[*:0]const u8) Entity {
        return c.ecs_entity_init(self.inner, &.{ .name = ident });
    }

    pub inline fn createEx(self: Self, desc: *const c.ecs_entity_desc_t) Entity {
        return c.ecs_entity_init(self.inner, desc);
    }

    pub inline fn delete(self: Self, ent: Entity) void {
        c.ecs_delete(self.inner, ent);
    }

    pub inline fn deleteWith(self: Self, id: Entity) void {
        c.ecs_delete_with(self.inner, id);
    }

    pub inline fn clear(self: Self, ent: Entity) void {
        c.ecs_clear(self.inner, ent);
    }

    // add

    pub inline fn add(self: Self, ent: Entity, comptime T: type) void {
        c.ecs_add_id(self.inner, ent, typeId(T));
    }

    pub inline fn addId(self: Self, ent: Entity, id: Entity) void {
        c.ecs_add_id(self.inner, ent, id);
    }

    pub inline fn addPair(self: Self, subject: Entity, first: Entity, second: Entity) void {
        c.ecs_add_id(self.inner, subject, pair(first, second));
    }

    pub inline fn addSingleton(self: Self, comptime T: type) void {
        self.add(typeId(T), T);
    }

    // remove

    pub inline fn remove(self: Self, ent: Entity, comptime T: type) void {
        return c.ecs_remove_id(self.inner, ent, typeId(T));
    }

    pub inline fn removeId(self: Self, ent: Entity, id: Entity) void {
        return c.ecs_remove_id(self.inner, ent, id);
    }

    pub inline fn removePair(self: Self, subject: Entity, first: Entity, second: Entity) void {
        return c.ecs_remove_id(self.inner, subject, pair(first, second));
    }

    // set

    pub inline fn setMetaName(self: Self, ent: Entity, new_name: [*:0]const u8) Entity {
        self.ensure(ent, components.Meta).?.*.setName(new_name) catch @panic("Failed to set meta name");
        return ent;
    }

    pub fn setPathName(self: Self, ent: Entity, new_name: ?[*:0]const u8) Entity {
        return c.ecs_set_name(self.inner, ent, new_name);
    }

    pub inline fn setUuid(self: Self, ent: Entity, uuid: Uuid) void {
        self.set(ent, components.Uuid, .{ .value = uuid });
    }

    pub inline fn set(self: Self, ent: Entity, comptime T: type, value: T) void {
        self.setId(ent, typeId(T), @sizeOf(T), @ptrCast(&value));
    }

    pub inline fn setId(self: Self, ent: Entity, comp: Entity, size: usize, value: *const anyopaque) void {
        c.ecs_set_id(self.inner, ent, comp, size, value);
    }

    pub inline fn setPair(
        self: Self,
        subject: Entity,
        first: Entity,
        second: Entity,
        comptime T: type,
        value: T,
    ) void {
        return c.ecs_set_id(self.inner, subject, pair(first, second), @sizeOf(T), @ptrCast(&value));
    }

    pub inline fn setSingleton(self: Self, comptime T: type, value: T) void {
        return self.set(typeId(T), T, value);
    }

    // get

    pub inline fn getId(self: Self, ent: Entity, id: Entity) ?*const anyopaque {
        return c.ecs_get_id(self.inner, ent, id);
    }

    pub inline fn getMutId(self: Self, ent: Entity, id: Entity) ?*anyopaque {
        return c.ecs_get_mut_id(self.inner, ent, id);
    }

    pub inline fn get(self: Self, ent: Entity, comptime T: type) ?*const T {
        return @ptrCast(@alignCast(self.getId(ent, typeId(T))));
    }

    pub inline fn getMut(self: Self, ent: Entity, comptime T: type) ?*T {
        return @ptrCast(@alignCast(self.getMutId(ent, typeId(T))));
    }

    pub inline fn getPair(self: Self, subject: Entity, first: Entity, second: Entity, comptime T: type) ?*T {
        const val = c.ecs_get_id(self.inner, subject, pair(first, second));
        return @ptrCast(@alignCast(val));
    }

    pub inline fn pairFirst(self: Self, p: Entity) Entity {
        return c.ecs_get_alive(self.inner, c.ECS_PAIR_FIRST(p));
    }

    pub inline fn pairSecond(self: Self, p: Entity) Entity {
        return c.ecs_get_alive(self.inner, c.ECS_PAIR_SECOND(p));
    }

    pub inline fn getTarget(self: Self, ent: Entity, rel: Entity, index: i32) Entity {
        return c.ecs_get_target(self.inner, ent, rel, index);
    }

    pub inline fn getParent(self: Self, ent: Entity) ?Entity {
        const parent = c.ecs_get_parent(self.inner, ent);
        if (parent == 0) {
            return null;
        } else {
            return parent;
        }
    }

    pub inline fn has(self: Self, ent: Entity, comptime T: type) bool {
        return c.ecs_has_id(self.inner, ent, typeId(T));
    }

    pub inline fn getAligned(self: Self, ent: Entity, comptime T: type, comptime alignment: usize) ?*align(alignment) const T {
        return @ptrCast(@alignCast(c.ecs_get_id(self.inner, ent, typeId(T))));
    }

    pub inline fn getMutAligned(self: Self, ent: Entity, comptime T: type, comptime alignment: usize) ?*align(alignment) T {
        return @ptrCast(@alignCast(c.ecs_get_mut_id(self.inner, ent, typeId(T))));
    }

    pub fn getType(self: Self, ent: Entity) ![]const Entity {
        const info = c.ecs_get_type(self.inner, ent) orelse return error.EntityNotFound;
        return info.*.array[0..@intCast(info.*.count)];
    }

    pub inline fn getName(self: Self, ent: Entity) [:0]const u8 {
        return if (c.ecs_get_name(self.inner, ent)) |name|
            std.mem.span(name)
        else
            self.getMetaName(ent);
    }

    pub inline fn ensure(self: Self, ent: Entity, comptime T: type) ?*T {
        return @ptrCast(@alignCast(c.ecs_ensure_id(self.inner, ent, typeId(T))));
    }

    pub inline fn getMetaName(self: Self, ent: Entity) [:0]const u8 {
        return if (self.get(ent, components.Meta)) |meta| std.mem.span(meta.name) else "";
    }

    pub inline fn getPathName(self: Self, ent: Entity) ?[:0]const u8 {
        return if (c.ecs_get_name(self.inner, ent)) |name| std.mem.span(name) else null;
    }

    pub inline fn getPathAlloc(self: Self, ent: Entity, allocator: std.mem.Allocator) ![:0]u8 {
        var buf = c.ECS_STRBUF_INIT;
        c.ecs_get_path_w_sep_buf(self.inner, 0, ent, ".", null, &buf, false);
        return try allocator.dupeZ(u8, buf.content[0..@intCast(buf.length)]);
    }

    pub inline fn getUuid(self: Self, ent: Entity) ?Uuid {
        const uuid_comp = self.get(ent, components.Uuid);
        return if (uuid_comp) |it| it.value else null;
    }

    pub inline fn getHierarchyOrder(self: Self, ent: Entity) u32 {
        return if (self.get(ent, components.HierarchyOrder)) |it| it.value else std.math.maxInt(u32);
    }

    pub inline fn progress(self: Self, dt: f32) bool {
        return c.ecs_progress(self.inner, dt);
    }

    pub inline fn query(self: Self, q: *const QueryDesc) *Query {
        return Query.from(c.ecs_query_init(self.inner, q));
    }

    pub inline fn isAlive(self: Self, ent: Entity) bool {
        return c.ecs_is_alive(self.inner, ent);
    }

    pub inline fn modified(self: Self, ent: Entity, comptime T: type) void {
        c.ecs_modified_id(self.inner, ent, typeId(T));
    }

    pub inline fn enable(self: Self, ent: Entity, enabled: bool) void {
        c.ecs_enable(self.inner, ent, enabled);
    }

    pub inline fn enableComponent(self: Self, ent: Entity, comptime T: type, enabled: bool) void {
        c.ecs_enable_id(self.inner, ent, typeId(T), enabled);
    }

    pub inline fn lookup(self: Self, path: [*:0]const u8) Entity {
        return c.ecs_lookup(self.inner, path);
    }

    pub inline fn lookupEx(self: Self, opts: struct {
        parent: Entity = 0,
        path: [*:0]const u8,
        recursive: bool = false,
    }) Entity {
        return c.ecs_lookup_path_w_sep(self.inner, opts.parent, opts.path, ".", null, opts.recursive);
    }

    pub inline fn hasAncestor(self: Self, ent: Entity, maybe_ancestor: Entity) bool {
        var it = ent;
        while (self.getParent(it)) |parent| : (it = parent) {
            if (parent == maybe_ancestor) {
                return true;
            }
        }
        return false;
    }

    // iterators

    pub inline fn children(self: Self, ent: Entity) Iterator {
        return Iterator{ .inner = c.ecs_children(self.inner, ent) };
    }

    pub fn childrenSorted(self: Self, ent: Entity, allocator: std.mem.Allocator) ![]Entity {
        var child_it = self.children(ent);
        defer child_it.deinit();

        // Create an array to collect entities
        var sorted_children = try std.ArrayList(Entity).initCapacity(allocator, @intCast(child_it.inner.count));
        while (child_it.next()) {
            for (0..@intCast(child_it.inner.count)) |i| {
                try sorted_children.append(child_it.inner.entities[i]);
            }
        }

        // Sort using a custom comparison function
        std.mem.sort(Entity, sorted_children.items, self, struct {
            pub fn f(ctx: Self, a: Entity, b: Entity) bool {
                return ctx.getHierarchyOrder(a) < ctx.getHierarchyOrder(b);
            }
        }.f);

        return try sorted_children.toOwnedSlice();
    }

    pub fn sortedDfs(self: Self, ent: Entity, allocator: std.mem.Allocator) !SortedDfs {
        return try SortedDfs.init(allocator, self, ent);
    }

    pub fn changeEntityOrder(self: Self, ent: Entity, new_order: u32, allocator: std.mem.Allocator) !void {
        // Get the parent of the entity
        const parent = self.getParent(ent) orelse return;

        // Fetch and sort all children of the parent
        const sorted_children = try self.childrenSorted(parent, allocator);
        defer allocator.free(sorted_children);

        // Check if the new order value already exists among the siblings
        var order_conflict = false;
        for (sorted_children) |child| {
            const current_order = if (self.get(child, components.HierarchyOrder)) |it| it.value else null;
            if (current_order == new_order) {
                order_conflict = true;
                break;
            }
        }

        // Resolve conflicts by incrementing order values of affected siblings
        if (order_conflict) {
            for (sorted_children) |child| {
                const current_order = self.getHierarchyOrder(child);
                if (current_order >= new_order) {
                    self.set(child, components.HierarchyOrder, .{ .value = current_order + 1 });
                }
            }
        }

        // Update the order for the specified entity
        self.set(ent, components.HierarchyOrder, .{ .value = new_order });

        // Re-sort siblings after resolving order conflicts
        std.mem.sort(Entity, sorted_children, self, struct {
            fn f(ctx: Self, a: Entity, b: Entity) bool {
                const ord_a = if (ctx.get(a, components.HierarchyOrder)) |it| it.value else 0;
                const ord_b = if (ctx.get(b, components.HierarchyOrder)) |it| it.value else 0;
                return ord_a < ord_b;
            }
        }.f);

        // Reassign continuous order values to all children
        for (sorted_children, 0..) |child, index| {
            self.set(child, components.HierarchyOrder, .{ .value = @intCast(index) });
        }
    }
};

pub const ResourceResolverResult = extern struct {
    found: bool,
    uuid: Uuid,
    type: assets.AssetType,

    pub fn toAssetHandle(rrr: ResourceResolverResult) !assets.AssetHandle {
        if (!rrr.found) return error.ResourceNotFound;
        return .{ .uuid = rrr.uuid, .type = rrr.type };
    }
};
pub const ResourceResolver = *const fn (path: [*:0]const u8) callconv(.C) ResourceResolverResult;

pub const SerializationResult = extern struct {
    ok: bool,
    result: Dynamic = Dynamic{ .type = .null, .value = .{ .null = {} } },
};

pub const ComponentDef = extern struct {
    id: Entity,
    icon: ?[*:0]const u8,
    billboard: ?[*:0]const u8,
    size: usize,
    alignment: usize,
    default: ?*const fn (self: *anyopaque, entity: Entity, ctx: *GameApp, resourceResolver: ResourceResolver) callconv(.C) bool,
    serialize: ?*const fn (self: *const anyopaque, allocator: *const std.mem.Allocator) callconv(.C) SerializationResult,
    deserialize: ?*const fn (self: *anyopaque, value: *const Dynamic, allocator: *const std.mem.Allocator) callconv(.C) bool,
};

fn Reflect(comptime T: type) type {
    const META = struct {
        const _ = T;
        var id: c.ecs_id_t = 0;
    };
    return META;
}

pub fn typeId(comptime T: type) c.ecs_id_t {
    return Reflect(T).id;
}

pub inline fn field(it: *Iterator, comptime T: type, index: i8) ?[]T {
    return fieldWithAlignment(it, T, @alignOf(T), index);
}

pub fn fieldWithAlignment(it: *Iterator, comptime T: type, comptime alignment: usize, index: i8) ?[]align(alignment) T {
    if (c.ecs_field_w_size(it.castMut(), @sizeOf(T), index)) |anyptr| {
        const ptr = @as([*]align(alignment) T, @ptrCast(@alignCast(anyptr)));
        return ptr[0..@intCast(it.inner.count)];
    }
    return null;
}

// taken from `zflecs` <https://github.com/zig-gamedev/zflecs/blob/ee2cd434fa2ec2454008988a1cc1201b242f030e/src/zflecs.zig#L2806C1-L2821C2>
// flecs internally reserves names like u16, u32, f32, etc. so we re-map them to uppercase to avoid collisions
pub fn typeName(comptime T: type) @TypeOf(@typeName(T)) {
    return switch (T) {
        u8 => return "U8",
        u16 => return "U16",
        u32 => return "U32",
        u64 => return "U64",
        i8 => return "I8",
        i16 => return "I16",
        i32 => return "I32",
        i64 => return "I64",
        f32 => return "F32",
        f64 => return "F64",
        else => return @typeName(T),
    };
}

pub const pair = c.ecs_pair;
pub fn isPair(id: Entity) bool {
    return c.ECS_IS_PAIR(id);
}

pub fn ids(comptime N: usize, args: [N]c.ecs_id_t) [*c]c.ecs_id_t {
    const len = N + 1;
    var result: [len]c.ecs_id_t = undefined;
    @memcpy(result[0..args.len], args[0..]);
    result[args.len] = 0;
    return result[0..];
}

pub const SortedDfs = struct {
    const Self = @This();

    world: World,
    stack: std.ArrayList(Entity),

    pub fn init(allocator: std.mem.Allocator, world: World, root: Entity) !Self {
        var self = Self{
            .world = world,
            .stack = try std.ArrayList(Entity).initCapacity(allocator, 1),
        };
        self.stack.appendAssumeCapacity(root);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
    }

    pub fn next(self: *Self) !?Entity {
        if (self.stack.items.len == 0) return null;

        const ent = self.stack.pop();
        var child_it = self.world.children(ent);
        defer child_it.deinit();

        // Create an array to collect entities
        var sorted_children = try std.ArrayList(Entity).initCapacity(self.stack.allocator, @intCast(child_it.inner.count));
        while (child_it.next()) {
            for (0..@intCast(child_it.inner.count)) |i| {
                try sorted_children.append(child_it.inner.entities[i]);
            }
        }

        // Sort using a custom comparison function
        std.mem.sort(Entity, sorted_children.items, self.world, struct {
            pub fn f(ctx: World, a: Entity, b: Entity) bool {
                return ctx.getHierarchyOrder(a) < ctx.getHierarchyOrder(b);
            }
        }.f);

        try self.stack.appendSlice(try sorted_children.toOwnedSlice());

        return ent;
    }

    // drains the iterator and returns all the items, calling deinit on the iterator is safe but unsavory
    pub fn collect(self: *Self) ![]Entity {
        var collected = std.ArrayList(Entity).init(self.stack.allocator);
        while (try self.next()) |nx| {
            try collected.append(nx);
        }
        self.stack.clearAndFree();
        return collected.items;
    }
};

// called on first world initialization, setting all static values
fn staticEsqueInitializer() void {
    id_flags.Pair = c.ECS_PAIR;
    id_flags.AutoOverride = c.ECS_AUTO_OVERRIDE;
    id_flags.Toggle = c.ECS_TOGGLE;

    core.Query = c.EcsQuery;
    core.Observer = c.EcsObserver;
    core.System = c.EcsSystem;
    core.Component = c.FLECS_IDEcsComponentID_;

    core.Wildcard = c.EcsWildcard;
    core.Any = c.EcsAny;
    core.This = c.EcsThis;
    core.Variable = c.EcsVariable;

    scopes.World = c.EcsWorld;
    scopes.Flecs = c.EcsFlecs;
    scopes.FlecsCore = c.EcsFlecsCore;
    scopes.Module = c.EcsModule;
    scopes.Private = c.EcsPrivate;
    scopes.Prefab = c.EcsPrefab;
    scopes.Disabled = c.EcsDisabled;
    scopes.NotQueryable = c.EcsNotQueryable;

    scopes.SlotOf = c.EcsSlotOf;

    traits.Transitive = c.EcsTransitive;
    traits.Reflexive = c.EcsReflexive;
    traits.Symmetric = c.EcsSymmetric;
    traits.Final = c.EcsFinal;
    traits.Inheritable = c.EcsInheritable;

    traits.OnInstantiate = c.EcsOnInstantiate;
    traits.Override = c.EcsOverride;
    traits.Inherit = c.EcsInherit;
    traits.DontInherit = c.EcsDontInherit;
    traits.PairIsTag = c.EcsPairIsTag;
    traits.Exclusive = c.EcsExclusive;
    traits.Acyclic = c.EcsAcyclic;
    traits.Traversable = c.EcsTraversable;
    traits.With = c.EcsWith;
    traits.OneOf = c.EcsOneOf;
    traits.CanToggle = c.EcsCanToggle;
    traits.Trait = c.EcsTrait;
    traits.Relationship = c.EcsRelationship;
    traits.Target = c.EcsTarget;

    identifier_tags.PathName = c.EcsName;
    identifier_tags.Symbol = c.EcsSymbol;
    identifier_tags.Alias = c.EcsAlias;

    std.debug.assert(@intFromEnum(Event.add) == c.EcsOnAdd);
    std.debug.assert(@intFromEnum(Event.remove) == c.EcsOnRemove);
    std.debug.assert(@intFromEnum(Event.set) == c.EcsOnSet);
    std.debug.assert(@intFromEnum(Event.delete) == c.EcsOnDelete);
    std.debug.assert(@intFromEnum(Event.deleteTarget) == c.EcsOnDeleteTarget);
    std.debug.assert(@intFromEnum(Event.tableCreate) == c.EcsOnTableCreate);
    std.debug.assert(@intFromEnum(Event.tableDelete) == c.EcsOnTableDelete);

    actions.Remove = c.EcsRemove;
    actions.Delete = c.EcsDelete;
    actions.Panic = c.EcsPanic;

    storage.Sparse = c.EcsSparse;
    storage.Union = c.EcsUnion;

    predicates.PredEq = c.EcsPredEq;
    predicates.PredMatch = c.EcsPredMatch;
    predicates.PredLookup = c.EcsPredLookup;
    predicates.ScopeOpen = c.EcsScopeOpen;
    predicates.ScopeClose = c.EcsScopeClose;

    systems.Monitor = c.EcsMonitor;
    systems.Empty = c.EcsEmpty;
    systems.OnStart = c.EcsOnStart;
    systems.PreFrame = c.EcsPreFrame;
    systems.OnLoad = c.EcsOnLoad;
    systems.PostLoad = c.EcsPostLoad;
    systems.PreUpdate = c.EcsPreUpdate;
    systems.OnUpdate = c.EcsOnUpdate;
    systems.OnValidate = c.EcsOnValidate;
    systems.PostUpdate = c.EcsPostUpdate;
    systems.PreStore = c.EcsPreStore;
    systems.OnStore = c.EcsOnStore;
    systems.PostFrame = c.EcsPostFrame;
    systems.Phase = c.EcsPhase;

    relations.ChildOf = c.EcsChildOf;
    relations.IsA = c.EcsIsA;
    relations.DependsOn = c.EcsDependsOn;

    query_miscs.Self = c.EcsSelf;
    query_miscs.Up = c.EcsUp;
    query_miscs.Trav = c.EcsTrav;
    query_miscs.Cascade = c.EcsCascade;
    query_miscs.Desc = c.EcsDesc;
    query_miscs.IsVariable = c.EcsIsVariable;
    query_miscs.IsEntity = c.EcsIsEntity;
    query_miscs.IsName = c.EcsIsName;
    query_miscs.TraverseFlags = c.EcsTraverseFlags;
    query_miscs.TermRefFlags = c.EcsTermRefFlags;

    operators.And = c.EcsAnd;
    operators.Or = c.EcsOr;
    operators.Not = c.EcsNot;
    operators.Optional = c.EcsOptional;
    operators.AndFrom = c.EcsAndFrom;
    operators.OrFrom = c.EcsOrFrom;
    operators.NotFrom = c.EcsNotFrom;

    std.debug.assert(@intFromEnum(InOut.default) == c.EcsInOutDefault);
    std.debug.assert(@intFromEnum(InOut.none) == c.EcsInOutNone);
    std.debug.assert(@intFromEnum(InOut.filter) == c.EcsInOutFilter);
    std.debug.assert(@intFromEnum(InOut.in_out) == c.EcsInOut);
    std.debug.assert(@intFromEnum(InOut.in) == c.EcsIn);
    std.debug.assert(@intFromEnum(InOut.out) == c.EcsOut);

    std.debug.assert(@intFromEnum(QueryCacheKind.default) == c.EcsQueryCacheDefault);
    std.debug.assert(@intFromEnum(QueryCacheKind.auto) == c.EcsQueryCacheAuto);
    std.debug.assert(@intFromEnum(QueryCacheKind.all) == c.EcsQueryCacheAll);
    std.debug.assert(@intFromEnum(QueryCacheKind.none) == c.EcsQueryCacheNone);
}

// Id flags
pub const id_flags = struct {
    pub var Pair: Entity = undefined;
    pub var AutoOverride: Entity = undefined;
    pub var Toggle: Entity = undefined;
};

pub const core = struct {
    // Poly target components
    pub var Query: Entity = undefined;
    pub var Observer: Entity = undefined;
    pub var System: Entity = undefined;
    pub var Component: Entity = undefined;

    // Marker entities for query encoding
    pub var Wildcard: Entity = undefined;
    pub var Any: Entity = undefined;
    pub var This: Entity = undefined;
    pub var Variable: Entity = undefined;
};

// Core scopes & entities
pub const scopes = struct {
    pub var World: Entity = undefined;
    pub var Flecs: Entity = undefined;
    pub var FlecsCore: Entity = undefined;
    pub var Module: Entity = undefined;
    pub var Private: Entity = undefined;
    pub var Prefab: Entity = undefined;
    pub var Disabled: Entity = undefined;
    pub var NotQueryable: Entity = undefined;

    pub var SlotOf: Entity = undefined;
};

// Traits
pub const traits = struct {
    pub var Transitive: Entity = undefined;
    pub var Reflexive: Entity = undefined;
    pub var Symmetric: Entity = undefined;
    pub var Final: Entity = undefined;
    pub var Inheritable: Entity = undefined;

    pub var OnInstantiate: Entity = undefined;
    pub var Override: Entity = undefined;
    pub var Inherit: Entity = undefined;
    pub var DontInherit: Entity = undefined;
    pub var PairIsTag: Entity = undefined;
    pub var Exclusive: Entity = undefined;
    pub var Acyclic: Entity = undefined;
    pub var Traversable: Entity = undefined;
    pub var With: Entity = undefined;
    pub var OneOf: Entity = undefined;
    pub var CanToggle: Entity = undefined;
    pub var Trait: Entity = undefined;
    pub var Relationship: Entity = undefined;
    pub var Target: Entity = undefined;
};

// Identifier tags
pub const identifier_tags = struct {
    pub var PathName: Entity = undefined;
    pub var Symbol: Entity = undefined;
    pub var Alias: Entity = undefined;
};

pub const Event = enum(Entity) {
    add = c.FLECS_HI_COMPONENT_ID + 40,
    remove = c.FLECS_HI_COMPONENT_ID + 41,
    set = c.FLECS_HI_COMPONENT_ID + 42,
    delete = c.FLECS_HI_COMPONENT_ID + 43,
    deleteTarget = c.FLECS_HI_COMPONENT_ID + 44,
    tableCreate = c.FLECS_HI_COMPONENT_ID + 45,
    tableDelete = c.FLECS_HI_COMPONENT_ID + 46,
};

// Actions
pub const actions = struct {
    pub var Remove: Entity = undefined;
    pub var Delete: Entity = undefined;
    pub var Panic: Entity = undefined;
};

// Storage
pub const storage = struct {
    pub var Sparse: Entity = undefined;
    pub var Union: Entity = undefined;
};

// Builtin predicate ids (used by query engine)
pub const predicates = struct {
    pub var PredEq: Entity = undefined;
    pub var PredMatch: Entity = undefined;
    pub var PredLookup: Entity = undefined;
    pub var ScopeOpen: Entity = undefined;
    pub var ScopeClose: Entity = undefined;
};

// Builtin relationships
pub const relations = struct {
    pub var ChildOf: Entity = undefined;
    pub var IsA: Entity = undefined;
    pub var DependsOn: Entity = undefined;
};

pub const query_miscs = struct {
    pub var Self: Entity = undefined;
    pub var Up: Entity = undefined;
    pub var Trav: Entity = undefined;
    pub var Cascade: Entity = undefined;
    pub var Desc: Entity = undefined;
    pub var IsVariable: Entity = undefined;
    pub var IsEntity: Entity = undefined;
    pub var IsName: Entity = undefined;
    pub var TraverseFlags: Entity = undefined;
    pub var TermRefFlags: Entity = undefined;
};

pub const operators = struct {
    pub var And: i16 = undefined;
    pub var Or: i16 = undefined;
    pub var Not: i16 = undefined;
    pub var Optional: i16 = undefined;
    pub var AndFrom: i16 = undefined;
    pub var OrFrom: i16 = undefined;
    pub var NotFrom: i16 = undefined;
};

pub const masks = struct {
    pub const idFlags = c.ECS_ID_FLAGS_MASK;
    pub const entity = c.ECS_ENTITY_MASK;
    pub const generation = c.ECS_GENERATION_MASK;
    pub const component = c.ECS_COMPONENT_MASK;
};

// Components
pub const components = struct {
    pub const Meta = @import("components/Meta.zig").Meta;
    pub const Uuid = @import("components/Uuid.zig").Uuid;

    pub const LocalTransform = @import("components/transform.zig").LocalTransform;
    pub const WorldTransform = @import("components/transform.zig").WorldTransform;

    pub const camera = @import("components/camera.zig");

    pub const lights = @import("components/lights.zig");

    pub const mesh = @import("components/mesh.zig");
    pub const material = @import("components/material.zig");

    pub const Camera = camera.Camera;

    pub const DirectionalLight = lights.DirectionalLight;
    pub const PointLight = lights.PointLight;

    pub const Mesh = mesh.Mesh;
    pub const Material = material.Material;

    pub const HierarchyOrder = @import("components/HierarchyOrder.zig").HierarchyOrder;
};

// Systems
pub const systems = struct {
    pub var Monitor: Entity = undefined;
    pub var Empty: Entity = undefined;
    pub var OnStart: Entity = undefined;
    pub var PreFrame: Entity = undefined;
    pub var OnLoad: Entity = undefined;
    pub var PostLoad: Entity = undefined;
    pub var PreUpdate: Entity = undefined;
    pub var OnUpdate: Entity = undefined;
    pub var OnValidate: Entity = undefined;
    pub var PostUpdate: Entity = undefined;
    pub var PreStore: Entity = undefined;
    pub var OnStore: Entity = undefined;
    pub var PostFrame: Entity = undefined;
    pub var Phase: Entity = undefined;

    pub const TransformSyncSystem = @import("systems/TransformSyncSystem.zig");
    pub const PostTransformSystem = @import("systems/PostTransformSystem.zig");
};

pub const InOut = enum(i16) {
    default = 0,
    none = 1,
    filter = 2,
    in_out = 3,
    in = 4,
    out = 5,

    pub inline fn cast(self: InOut) i16 {
        return @intFromEnum(self);
    }
};

pub const QueryCacheKind = enum(c_int) {
    default = 0,
    auto = 1,
    all = 2,
    none = 3,

    pub inline fn cast(self: QueryCacheKind) i16 {
        return @intFromEnum(self);
    }
};

/// Taken from <https://github.com/zig-gamedev/zflecs/blob/ee2cd434fa2ec2454008988a1cc1201b242f030e/src/zflecs.zig#L2652C1-L2693C2>
/// Implements a flecs system from function parameters.
/// For instance, the function below
/// fn move_system(positions: []Position, velocities: []const Velocity) void {
///     for (positions, velocities) |*p, *v| {
///         p.x += v.x;
///         p.y += v.y;
///     }
/// }
/// Would return the following implementation
/// fn exec(it: *ecs.iter_t) callconv(.C) void {
///     const c1 = ecs.field(it, Position, 0).?;
///     const c2 = ecs.field(it, Velocity, 1).?;
///     move_system(c1, c2);//probably inlined
// }
pub fn SystemImpl(comptime fn_system: anytype) type {
    const fn_type = @typeInfo(@TypeOf(fn_system));
    switch (fn_type) {
        .Fn => |f| if (f.params.len == 0) {
            @compileError("System need at least one parameter");
        },
        else => @compileError("System should be a pure function"),
    }

    return struct {
        pub fn exec(it: [*c]c.ecs_iter_t) callconv(.C) void {
            const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(fn_system));
            var args_tuple: ArgsTupleType = undefined;

            const has_it_param = comptime hasItParam(fn_type.Fn.params);
            if (has_it_param) {
                if (fn_type.Fn.params[0].type == *Iter) {
                    args_tuple[0] = @ptrCast(it);
                } else {
                    args_tuple[0] = it;
                }
            }

            const start_index = if (has_it_param) 1 else 0;

            inline for (start_index..fn_type.Fn.params.len) |i| {
                const p = fn_type.Fn.params[i];
                const info = @typeInfo(p.type.?);
                args_tuple[i] = field(Iterator.from(it), info.Pointer.child, i - start_index).?;
            }

            _ = @call(.auto, fn_system, args_tuple);
        }
    };
}

fn hasItParam(comptime params: []const std.builtin.Type.Fn.Param) bool {
    return params[0].type == *c.ecs_iter_t or params[0].type == *Iter;
}

// ECS OS allocator API
// TODO: define allocator in zig world and expose it to C instead of doing this
// It doesn't use arena which is undesired
pub inline fn malloc(size: usize) std.mem.Allocator.Error!*anyopaque {
    return c.ecs_os_api.malloc_.?(@intCast(size)) orelse return error.OutOfMemory;
}

pub inline fn free(ptr: *anyopaque) void {
    return c.ecs_os_api.free_.?(ptr);
}

pub inline fn realloc(ptr: *anyopaque, size: usize) std.mem.Allocator.Error!*anyopaque {
    return c.ecs_os_api.realloc_.?(ptr, @intCast(size)) orelse return error.OutOfMemory;
}

pub inline fn calloc(size: usize) std.mem.Allocator.Error!*anyopaque {
    return c.ecs_os_api.calloc_.?(@intCast(size)) orelse return error.OutOfMemory;
}

// monkey patches for working around zig compiler bugs

const mkp_system_init = ecs_system_init;
extern fn ecs_system_init(world: ?*c.ecs_world_t, desc: [*c]const SystemDesc) c.ecs_entity_t;

pub const SystemDesc = extern struct {
    _canary: i32 = @import("std").mem.zeroes(i32),
    entity: c.ecs_entity_t = @import("std").mem.zeroes(c.ecs_entity_t),
    query: c.ecs_query_desc_t = @import("std").mem.zeroes(c.ecs_query_desc_t),
    callback: ?*const fn (it: *Iter) callconv(.C) void = @import("std").mem.zeroes(?*const fn (it: *Iter) callconv(.C) void),
    run: c.ecs_run_action_t = @import("std").mem.zeroes(c.ecs_run_action_t),
    ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    ctx_free: c.ecs_ctx_free_t = @import("std").mem.zeroes(c.ecs_ctx_free_t),
    callback_ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    callback_ctx_free: c.ecs_ctx_free_t = @import("std").mem.zeroes(c.ecs_ctx_free_t),
    run_ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    run_ctx_free: c.ecs_ctx_free_t = @import("std").mem.zeroes(c.ecs_ctx_free_t),
    interval: f32 = @import("std").mem.zeroes(f32),
    rate: i32 = @import("std").mem.zeroes(i32),
    tick_source: c.ecs_entity_t = @import("std").mem.zeroes(c.ecs_entity_t),
    multi_threaded: bool = @import("std").mem.zeroes(bool),
    immediate: bool = @import("std").mem.zeroes(bool),
};

pub const ObserverDesc = extern struct {
    _canary: i32 = @import("std").mem.zeroes(i32),
    entity: c.ecs_entity_t = @import("std").mem.zeroes(c.ecs_entity_t),
    query: c.ecs_query_desc_t = @import("std").mem.zeroes(c.ecs_query_desc_t),
    events: [8]c.ecs_entity_t = @import("std").mem.zeroes([8]c.ecs_entity_t),
    yield_existing: bool = @import("std").mem.zeroes(bool),
    callback: ?*const fn (it: *Iter) callconv(.C) void = @import("std").mem.zeroes(?*const fn (it: *Iter) callconv(.C) void),
    run: c.ecs_run_action_t = @import("std").mem.zeroes(c.ecs_run_action_t),
    ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    ctx_free: c.ecs_ctx_free_t = @import("std").mem.zeroes(c.ecs_ctx_free_t),
    callback_ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    callback_ctx_free: c.ecs_ctx_free_t = @import("std").mem.zeroes(c.ecs_ctx_free_t),
    run_ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    run_ctx_free: c.ecs_ctx_free_t = @import("std").mem.zeroes(c.ecs_ctx_free_t),
    observable: ?*c.ecs_poly_t = @import("std").mem.zeroes(?*c.ecs_poly_t),
    last_event_id: [*c]i32 = @import("std").mem.zeroes([*c]i32),
    term_index_: i8 = @import("std").mem.zeroes(i8),
    flags_: c.ecs_flags32_t = @import("std").mem.zeroes(c.ecs_flags32_t),
};

pub const Iter = extern struct {
    world: ?*c.ecs_world_t = @import("std").mem.zeroes(?*c.ecs_world_t),
    real_world: ?*c.ecs_world_t = @import("std").mem.zeroes(?*c.ecs_world_t),
    entities: [*c]const c.ecs_entity_t = @import("std").mem.zeroes([*c]const c.ecs_entity_t),
    sizes: [*c]const c.ecs_size_t = @import("std").mem.zeroes([*c]const c.ecs_size_t),
    table: ?*c.ecs_table_t = @import("std").mem.zeroes(?*c.ecs_table_t),
    other_table: ?*c.ecs_table_t = @import("std").mem.zeroes(?*c.ecs_table_t),
    ids: [*c]c.ecs_id_t = @import("std").mem.zeroes([*c]c.ecs_id_t),
    variables: [*c]c.ecs_var_t = @import("std").mem.zeroes([*c]c.ecs_var_t),
    trs: [*c][*c]const c.ecs_table_record_t = @import("std").mem.zeroes([*c][*c]const c.ecs_table_record_t),
    sources: [*c]c.ecs_entity_t = @import("std").mem.zeroes([*c]c.ecs_entity_t),
    constrained_vars: c.ecs_flags64_t = @import("std").mem.zeroes(c.ecs_flags64_t),
    group_id: u64 = @import("std").mem.zeroes(u64),
    set_fields: c.ecs_flags32_t = @import("std").mem.zeroes(c.ecs_flags32_t),
    ref_fields: c.ecs_flags32_t = @import("std").mem.zeroes(c.ecs_flags32_t),
    row_fields: c.ecs_flags32_t = @import("std").mem.zeroes(c.ecs_flags32_t),
    up_fields: c.ecs_flags32_t = @import("std").mem.zeroes(c.ecs_flags32_t),
    system: c.ecs_entity_t = @import("std").mem.zeroes(c.ecs_entity_t),
    event: c.ecs_entity_t = @import("std").mem.zeroes(c.ecs_entity_t),
    event_id: c.ecs_id_t = @import("std").mem.zeroes(c.ecs_id_t),
    event_cur: i32 = @import("std").mem.zeroes(i32),
    field_count: i8 = @import("std").mem.zeroes(i8),
    term_index: i8 = @import("std").mem.zeroes(i8),
    variable_count: i8 = @import("std").mem.zeroes(i8),
    query: [*c]const c.ecs_query_t = @import("std").mem.zeroes([*c]const c.ecs_query_t),
    variable_names: [*c][*c]u8 = @import("std").mem.zeroes([*c][*c]u8),
    param: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    binding_ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    callback_ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    run_ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    delta_time: f32 = @import("std").mem.zeroes(f32),
    delta_system_time: f32 = @import("std").mem.zeroes(f32),
    frame_offset: i32 = @import("std").mem.zeroes(i32),
    offset: i32 = @import("std").mem.zeroes(i32),
    count: i32 = @import("std").mem.zeroes(i32),
    flags: c.ecs_flags32_t = @import("std").mem.zeroes(c.ecs_flags32_t),
    interrupted_by: c.ecs_entity_t = @import("std").mem.zeroes(c.ecs_entity_t),
    priv_: c.ecs_iter_private_t = @import("std").mem.zeroes(c.ecs_iter_private_t),
    next: ?*const fn ([*c]c.ecs_iter_t) callconv(.C) bool = @import("std").mem.zeroes(?*const fn ([*c]c.ecs_iter_t) callconv(.C) bool),
    callback: ?*const fn (it: *c.ecs_iter_t) callconv(.C) void = @import("std").mem.zeroes(?*const fn (it: *c.ecs_iter_t) callconv(.C) void),
    fini: c.ecs_iter_fini_action_t = @import("std").mem.zeroes(c.ecs_iter_fini_action_t),
    chain_it: [*c]c.ecs_iter_t = @import("std").mem.zeroes([*c]c.ecs_iter_t),
};

pub const IterAction = ?*const fn ([*c]c.ecs_iter_t) callconv(.C) void;

pub const ComponentDesc = extern struct {
    _canary: i32 = @import("std").mem.zeroes(i32),
    entity: c.ecs_entity_t = @import("std").mem.zeroes(c.ecs_entity_t),
    type: TypeInfo = @import("std").mem.zeroes(TypeInfo),
};

pub const TypeInfo = extern struct {
    size: c.ecs_size_t = @import("std").mem.zeroes(c.ecs_size_t),
    alignment: c.ecs_size_t = @import("std").mem.zeroes(c.ecs_size_t),
    hooks: TypeHooks = @import("std").mem.zeroes(TypeHooks),
    component: c.ecs_entity_t = @import("std").mem.zeroes(c.ecs_entity_t),
    name: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
};

pub const TypeHooks = extern struct {
    ctor: Xtor = @import("std").mem.zeroes(Xtor),
    dtor: Xtor = @import("std").mem.zeroes(Xtor),
    copy: Copy = @import("std").mem.zeroes(Copy),
    move: Move = @import("std").mem.zeroes(Move),
    copy_ctor: Copy = @import("std").mem.zeroes(Copy),
    move_ctor: Move = @import("std").mem.zeroes(Move),
    ctor_move_dtor: Move = @import("std").mem.zeroes(Move),
    move_dtor: Move = @import("std").mem.zeroes(Move),
    cmp: Cmp = @import("std").mem.zeroes(Cmp),
    equals: Equals = @import("std").mem.zeroes(Equals),
    flags: c.ecs_flags32_t = @import("std").mem.zeroes(c.ecs_flags32_t),
    on_add: IterAction = @import("std").mem.zeroes(IterAction),
    on_set: IterAction = @import("std").mem.zeroes(IterAction),
    on_remove: IterAction = @import("std").mem.zeroes(IterAction),
    ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    binding_ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    lifecycle_ctx: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    ctx_free: c.ecs_ctx_free_t = @import("std").mem.zeroes(c.ecs_ctx_free_t),
    binding_ctx_free: c.ecs_ctx_free_t = @import("std").mem.zeroes(c.ecs_ctx_free_t),
    lifecycle_ctx_free: c.ecs_ctx_free_t = @import("std").mem.zeroes(c.ecs_ctx_free_t),
};

pub const Xtor = ?*const fn (?*anyopaque, i32, [*c]const TypeInfo) callconv(.C) void;
pub const Copy = ?*const fn (?*anyopaque, ?*const anyopaque, i32, [*c]const TypeInfo) callconv(.C) void;
pub const Move = ?*const fn (?*anyopaque, ?*anyopaque, i32, [*c]const TypeInfo) callconv(.C) void;
pub const Cmp = ?*const fn (?*const anyopaque, ?*const anyopaque, [*c]const TypeInfo) callconv(.C) c_int;
pub const Equals = ?*const fn (?*const anyopaque, ?*const anyopaque, [*c]const TypeInfo) callconv(.C) bool;

const mkp_component_init = ecs_component_init;
extern fn ecs_component_init(world: *c.ecs_world_t, desc: *const ComponentDesc) Entity;
