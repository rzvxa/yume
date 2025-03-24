const c = @import("clibs");
const std = @import("std");

const utils = @import("utils.zig");

pub const Entity = c.ecs_entity_t;
pub const Query = c.ecs_query_t;

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

    pub fn register(self: Self, comptime T: type) void {
        if (@sizeOf(T) == 0) {
            return self.registerTag(T);
        } else {
            return self.registerComponent(T);
        }
    }

    pub fn registerComponent(self: Self, comptime T: type) void {
        if (@sizeOf(T) == 0) {
            @compileError("For registering zero-sized components use `registerTag` instead");
        }

        const meta = Reflect(T);
        std.debug.assert(meta.id == 0);

        meta.id = c.ecs_component_init(self.inner, &.{
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
                        .@"struct" => if (@hasDecl(T, "deinit")) struct {
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
    }

    pub fn registerTag(self: Self, comptime T: type) void {
        if (@sizeOf(T) != 0) {
            @compileError("For registering non-zero-sized components use `registerComponent` instead");
        }

        const meta = Reflect(T);
        std.debug.assert(meta.id == 0);

        meta.id = c.ecs_entity_init(self.inner, &.{ .name = typeName(T) });
    }

    pub fn createEntity(self: Self, name: [:0]const u8) Entity {
        return c.ecs_entity_init(self.inner, &.{ .name = name });
    }

    pub fn destroyEntity(self: Self, entity: Entity) void {
        c.ecs_delete(self.inner, entity);
    }

    pub fn add(self: Self, entity: Entity, comptime T: type) void {
        c.ecs_add_id(self.inner, entity, typeId(T));
    }

    pub fn set(self: Self, entity: Entity, comptime T: type, value: T) void {
        c.ecs_set_id(self.inner, entity, typeId(T), @sizeOf(T), @ptrCast(&value));
    }

    pub fn addPair(self: Self, entity: Entity, first: Entity, second: Entity) void {
        c.ecs_add_id(self.inner, entity, c.ecs_pair(first, second));
    }

    pub fn get(self: Self, entity: Entity, comptime T: type) *const T {
        return @ptrCast(@alignCast(c.ecs_get_id(self.inner, entity, typeId(T))));
    }

    pub fn getMut(self: Self, entity: Entity, comptime T: type) *T {
        return @ptrCast(@alignCast(c.ecs_get_mut_id(self.inner, entity, typeId(T))));
    }

    pub fn progress(self: Self, dt: f32) bool {
        return c.ecs_progress(self.inner, dt);
    }

    pub fn query(self: Self, q: Query) bool {
        return c.ecs_query_init(self.inner, q);
    }
};

fn Reflect(comptime T: type) type {
    const META = struct {
        const _ = T;
        var id: c.ecs_id_t = 0;
    };
    return META;
}

fn typeId(comptime T: type) c.ecs_id_t {
    return Reflect(T).id;
}

// taken from `zflecs` <https://github.com/zig-gamedev/zflecs/blob/ee2cd434fa2ec2454008988a1cc1201b242f030e/src/zflecs.zig#L2806C1-L2821C2>
// flecs internally reserves names like u16, u32, f32, etc. so we re-map them to uppercase to avoid collisions
fn typeName(comptime T: type) @TypeOf(@typeName(T)) {
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

// called on first world initialization, setting all static values
fn staticEsqueInitializer() void {
    id_flags.Pair = c.ECS_PAIR;
    id_flags.AutoOverride = c.ECS_AUTO_OVERRIDE;
    id_flags.Toggle = c.ECS_TOGGLE;

    core.Query = c.EcsQuery;
    core.Observer = c.EcsObserver;
    core.System = c.EcsSystem;

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
