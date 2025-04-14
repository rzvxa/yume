const c = @import("clibs");
const std = @import("std");

const GameApp = @import("GameApp.zig");

pub const TypeId = c.ecs_id_t;
pub const Entity = c.ecs_entity_t;
pub const System = c.ecs_system_desc_t;
pub const QueryDesc = c.ecs_query_desc_t;
pub const Iterator = c.ecs_iter_t;

pub const Query = extern struct {
    const Self = @This();
    inner: c.ecs_query_t,

    pub fn deinit(self: *Self) void {
        c.ecs_query_fini(self.castMut());
    }

    pub fn iter(self: *const Self) Iterator {
        return c.ecs_query_iter(self.inner.world orelse self.inner.real_world.?, self.cast());
    }

    fn cast(self: *const Self) *const c.ecs_query_t {
        return @ptrCast(self);
    }

    fn castMut(self: *Self) *c.ecs_query_t {
        return @ptrCast(self);
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
                            pub fn f(ptr: *anyopaque, _: i32, _: *const c.ecs_type_info_t) callconv(.C) void {
                                T.deinit(@as(*T, @ptrCast(@alignCast(ptr))).*);
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
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
            .default = switch (@typeInfo(T)) {
                .Struct => if (@hasDecl(T, "default")) struct {
                    pub fn f(ptr: *anyopaque, entity: Entity, ctx: *GameApp) callconv(.C) bool {
                        return T.default(@as(*align(8) T, @ptrCast(@alignCast(ptr))), entity, ctx);
                    }
                }.f else null,
                else => null,
            },
        };
    }

    pub fn autoSystemFnDesc(comptime fn_system: anytype) c.ecs_system_desc_t {
        var terms = std.mem.zeroes([32]c.ecs_term_t);
        const fn_type = @typeInfo(@TypeOf(fn_system)).Fn;
        const has_it_param = fn_type.params[0].type == *c.ecs_iter_t;
        const start_index = if (has_it_param) 1 else 0;
        inline for (start_index..fn_type.params.len) |i| {
            const p = fn_type.params[i];
            const param_type_info = @typeInfo(p.type.?).Pointer;
            const inout = if (param_type_info.is_const) c.EcsIn else c.EcsInOut;
            terms[i - start_index] = .{ .id = typeId(param_type_info.child), .inout = inout };
        }
        return systemFnDesc(fn_system, terms);
    }

    pub fn systemFnDesc(comptime fn_system: anytype, terms: [32]c.ecs_term_t) c.ecs_system_desc_t {
        const system_struct = SystemImpl(fn_system);

        var system_desc = System{};
        system_desc.callback = system_struct.exec;
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
        system_desc: *c.ecs_system_desc_t,
    ) Entity {
        var entity_desc = c.ecs_entity_desc_t{};
        entity_desc.id = c.ecs_new(self.inner);
        entity_desc.name = name;
        const first = if (phase != 0) pair(relations.DependsOn, phase) else 0;
        const second = phase;
        entity_desc.add = &[_]c.ecs_id_t{ first, second, 0 };

        system_desc.entity = self.createEx(&entity_desc);
        return c.ecs_system_init(self.inner, system_desc);
    }

    pub fn systemEx(self: Self, desc: SystemDesc) Entity {
        return mkp_system_init(self.inner, &desc);
    }

    pub fn create(self: Self, name: [*:0]const u8) Entity {
        return c.ecs_entity_init(self.inner, &.{ .name = name });
    }

    pub fn createEx(self: Self, desc: *const c.ecs_entity_desc_t) Entity {
        return c.ecs_entity_init(self.inner, desc);
    }

    pub fn delete(self: Self, ent: Entity) void {
        c.ecs_delete(self.inner, ent);
    }

    pub fn clear(self: Self, ent: Entity) void {
        c.ecs_clear(self.inner, ent);
    }

    // add

    pub fn add(self: Self, ent: Entity, comptime T: type) void {
        c.ecs_add_id(self.inner, ent, typeId(T));
    }

    pub fn addId(self: Self, ent: Entity, id: Entity) void {
        c.ecs_add_id(self.inner, ent, id);
    }

    pub fn addPair(self: Self, subject: Entity, first: Entity, second: Entity) void {
        c.ecs_add_id(self.inner, subject, pair(first, second));
    }

    pub fn addSingleton(self: Self, comptime T: type) void {
        self.add(typeId(T), T);
    }

    // remove

    pub fn remove(self: Self, ent: Entity, comptime T: type) void {
        return c.ecs_remove_id(self.inner, ent, typeId(T));
    }

    pub fn removeId(self: Self, ent: Entity, id: Entity) void {
        return c.ecs_remove_id(self.inner, ent, id);
    }

    pub fn removePair(self: Self, subject: Entity, first: Entity, second: Entity) void {
        return c.ecs_remove_id(self.inner, subject, pair(first, second));
    }

    // set

    pub fn setName(self: Self, ent: Entity, new_name: [*:0]const u8) Entity {
        return c.ecs_set_name(self.inner, ent, new_name);
    }

    pub fn set(self: Self, ent: Entity, comptime T: type, value: T) void {
        self.setId(ent, typeId(T), @sizeOf(T), @ptrCast(&value));
    }

    pub inline fn setId(self: Self, ent: Entity, comp: Entity, size: usize, value: *const anyopaque) void {
        c.ecs_set_id(self.inner, ent, comp, size, value);
    }

    pub fn setPair(
        self: Self,
        subject: Entity,
        first: Entity,
        second: Entity,
        comptime T: type,
        value: T,
    ) void {
        return c.ecs_set_id(self.inner, subject, pair(first, second), @sizeOf(T), @ptrCast(&value));
    }

    pub fn setSingleton(self: Self, comptime T: type, value: T) void {
        return self.set(typeId(T), T, value);
    }

    // get

    pub fn get(self: Self, ent: Entity, comptime T: type) *const T {
        return @ptrCast(@alignCast(c.ecs_get_id(self.inner, ent, typeId(T))));
    }

    pub fn getMut(self: Self, ent: Entity, comptime T: type) *T {
        return @ptrCast(@alignCast(c.ecs_get_mut_id(self.inner, ent, typeId(T))));
    }

    pub fn getName(self: Self, ent: Entity) [:0]const u8 {
        return if (c.ecs_get_name(self.inner, ent)) |name| std.mem.span(name) else "";
    }

    pub fn progress(self: Self, dt: f32) bool {
        return c.ecs_progress(self.inner, dt);
    }

    pub fn query(self: Self, q: *const QueryDesc) *Query {
        return @ptrCast(c.ecs_query_init(self.inner, q));
    }

    pub fn enable(self: Self, ent: Entity, enabled: bool) void {
        c.ecs_enable(self.inner, ent, enabled);
    }

    pub fn enable_component(self: Self, ent: Entity, comptime T: type, enabled: bool) void {
        c.ecs_enable_id(self.inner, ent, typeId(T), enabled);
    }

    // iterators

    pub fn children(self: Self, ent: Entity) c.ecs_iter_t {
        return c.ecs_children(self.inner, ent);
    }
};

pub const ComponentDef = extern struct {
    id: Entity,
    size: usize,
    alignment: usize,
    default: ?*const fn (self: *anyopaque, entity: Entity, ctx: *GameApp) callconv(.C) bool,
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

pub fn field(it: *c.ecs_iter_t, comptime T: type, index: i8) ?[]T {
    if (c.ecs_field_w_size(it, @sizeOf(T), index)) |anyptr| {
        const ptr = @as([*]T, @ptrCast(@alignCast(anyptr)));
        return ptr[0..@intCast(it.count)];
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

pub fn ids(comptime N: usize, args: [N]c.ecs_id_t) [*c]c.ecs_id_t {
    const len = N + 1;
    var result: [len]c.ecs_id_t = undefined;
    @memcpy(result[0..args.len], args[0..]);
    result[args.len] = 0;
    return result[0..];
}

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

    identifier_tags.Name = c.EcsName;
    identifier_tags.Symbol = c.EcsSymbol;
    identifier_tags.Alias = c.EcsAlias;

    events.OnAdd = c.EcsOnAdd;
    events.OnRemove = c.EcsOnRemove;
    events.OnSet = c.EcsOnSet;
    events.OnDelete = c.EcsOnDelete;
    events.OnDeleteTarget = c.EcsOnDeleteTarget;
    events.OnTableCreate = c.EcsOnTableCreate;
    events.OnTableDelete = c.EcsOnTableDelete;

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

    operators.And = c.EcsAnd;
    operators.Or = c.EcsOr;
    operators.Not = c.EcsNot;
    operators.Optional = c.EcsOptional;
    operators.AndFrom = c.EcsAndFrom;
    operators.OrFrom = c.EcsOrFrom;
    operators.NotFrom = c.EcsNotFrom;
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
    pub var Name: Entity = undefined;
    pub var Symbol: Entity = undefined;
    pub var Alias: Entity = undefined;
};

// Events
pub const events = struct {
    pub var OnAdd: Entity = undefined;
    pub var OnRemove: Entity = undefined;
    pub var OnSet: Entity = undefined;
    pub var OnDelete: Entity = undefined;
    pub var OnDeleteTarget: Entity = undefined;
    pub var OnTableCreate: Entity = undefined;
    pub var OnTableDelete: Entity = undefined;
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
};

// Builtin relationships
pub const relations = struct {
    pub var ChildOf: Entity = undefined;
    pub var IsA: Entity = undefined;
    pub var DependsOn: Entity = undefined;
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
        fn exec(it: [*c]c.ecs_iter_t) callconv(.C) void {
            const ArgsTupleType = std.meta.ArgsTuple(@TypeOf(fn_system));
            var args_tuple: ArgsTupleType = undefined;

            const has_it_param = fn_type.Fn.params[0].type == *c.ecs_iter_t;
            if (has_it_param) {
                args_tuple[0] = it;
            }

            const start_index = if (has_it_param) 1 else 0;

            inline for (start_index..fn_type.Fn.params.len) |i| {
                const p = fn_type.Fn.params[i];
                args_tuple[i] = field(it, @typeInfo(p.type.?).Pointer.child, i - start_index).?;
            }

            //NOTE: .always_inline seems ok, but unsure. Replace to .auto if it breaks
            _ = @call(.always_inline, fn_system, args_tuple);
        }
    };
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
