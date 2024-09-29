const std = @import("std");
const Allocator = std.mem.Allocator;

const TypeId = @import("TypeId.zig");
const collections = @import("../root.zig").collections;
const IndexMap = collections.IndexMap;
const List = collections.List;

const Entities = List(Entity);
const Groups = IndexMap(GroupId, Group);

const Shapes = std.HashMap(Shape, GroupId, ShapeHashContext, std.hash_map.default_max_load_percentage);

/// Don't initialize or modify it manually.
pub const Entity = struct {
    index: u32,
    group: GroupId,

    /// Does this entity have any components?
    pub inline fn isEmpty(self: Entity) bool {
        return self.group.index == 0;
    }

    pub inline fn shape(self: Entity, reg: *const Registry) *const Shape {
        const group = reg.groups.items[self.group.index];
        return &group.shape;
    }
};

/// Don't initialize or modify it manually.
pub const GroupId = struct {
    index: u32,
};

/// Don't initialize or modify it manually.
pub const Group = struct {
    shape: Shape,
    columns: []*anyopaque,

    fn create(alloc: Allocator, shape: Shape) EcsError!Group {
        return .{ .shape = shape, .columns = alloc.alloc(*anyopaque, 0) catch return EcsError.OutOfMemory };
    }

    fn destroy(self: Group, alloc: Allocator) void {
        alloc.free(self.columns);
    }
};

/// Don't initialize these manually, Only use the static methods to construct one otherwise you might endup with unsound code.
const Shape = struct {
    components: List(TypeId),

    fn create(components: List(TypeId)) Shape {
        const self = Shape{ .components = components };
        std.mem.sort(TypeId, self.components.items, {}, comptime TypeId.sort);
        return self;
    }

    fn destroy(self: Shape) void {
        List(TypeId).deinit(self.components);
    }

    fn clone(self: *const Shape) EcsError!Shape {
        return .{ .components = self.components.clone() catch return EcsError.OutOfMemory };
    }
};

const ShapeHashContext = struct {
    pub fn hash(ctx: ShapeHashContext, key: Shape) u64 {
        _ = ctx;
        var h = std.hash.Crc32.init();
        for (key.components.items) |comp| {
            h.update(&std.mem.toBytes(comp.raw));
        }
        return h.final();
    }

    pub fn eql(ctx: ShapeHashContext, a: Shape, b: Shape) bool {
        _ = ctx;
        if (a.components.items.len != b.components.items.len) {
            return false;
        }

        for (a.components.items, b.components.items) |a_comp, b_comp| {
            if (!a_comp.eql(b_comp)) {
                return false;
            }
        }
        return true;
    }
};

pub const Registry = struct {
    allocator: Allocator,
    entities: Entities,
    // TODO: don't allow it to use the `maxInt(u32)` index.
    groups: Groups,
    shapes: Shapes,

    pub inline fn init(allocator: Allocator) EcsError!Registry {
        var self = Registry{
            .allocator = allocator,
            .entities = Entities.init(allocator),
            .groups = Groups.init(allocator),
            .shapes = Shapes.init(allocator),
        };
        _ = try self.getGroup(Shape.create(List(TypeId).init(allocator)));
        return self;
    }

    pub inline fn deinit(self: Registry) void {
        Entities.deinit(self.entities);
        Groups.deinit(self.groups);
    }

    pub fn newEntity(self: *Registry) Entity {
        _ = self;
        return .{ .index = 0, .group = .{ .index = 0 } };
    }

    pub fn addComponent(self: *Registry, entity: Entity, component: anytype) EcsError!void {
        const comp_id = TypeId.new(@TypeOf(component));

        const shape = entity.shape(self);
        for (shape.components.items) |it| {
            if (it.eql(comp_id)) {
                return EcsError.DuplicateComponent;
            }
        }

        var new_shape = try shape.clone();
        new_shape.components.append(comp_id) catch return EcsError.OutOfMemory;
        const group = try self.getGroup(new_shape);
        std.debug.print("{}", .{group});
    }

    fn getGroup(self: *Registry, shape: Shape) EcsError!*Group {
        if (self.shapes.get(shape)) |group| {
            // if group already exists we don't need our input shape anymore.
            shape.destroy();
            return &self.groups.items[group.index];
        } else {
            const index = @as(u32, @truncate(self.groups.items.len));
            self.groups.append(try Group.create(self.allocator, shape)) catch return EcsError.OutOfMemory;
            const group_id = GroupId{ .index = index };
            try self.shapes.put(shape, group_id);
            return self.getGroup(shape);
        }
    }
};

pub const EcsError = error{ DuplicateComponent, OutOfMemory };
