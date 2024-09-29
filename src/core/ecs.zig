const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
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

    pub inline fn shape(self: Entity, reg: *Registry) Shape {
        const group = reg.groups.items[self.group.index];
        return group.shape;
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
};

/// Don't initialize these manually, Only use the static methods to construct one otherwise you might endup with unsound code.
const Shape = struct {
    components: [][:0]const u8,

    fn fromUnordered(components: [][:0]const u8) Shape {
        const self = Shape{ .components = components };
        std.mem.sort([:0]const u8, self.components, {}, comptime Shape.sort);
        return self;
    }

    fn sort(_: void, lhs: [:0]const u8, rhs: [:0]const u8) bool {
        return std.mem.order(u8, lhs, rhs) == .lt;
    }
};

const ShapeHashContext = struct {
    pub fn hash(ctx: ShapeHashContext, key: Shape) u64 {
        _ = ctx;
        var h = std.hash.Crc32.init();
        for (key.components) |comp| {
            h.update(comp);
        }
        return h.final();
    }

    pub fn eql(ctx: ShapeHashContext, a: Shape, b: Shape) bool {
        _ = ctx;
        if (a.components.len != b.components.len) {
            return false;
        }

        for (a.components, b.components) |a_comp, b_comp| {
            if (!std.mem.eql(u8, a_comp, b_comp)) {
                return false;
            }
        }
        return true;
    }
};

pub const Registry = struct {
    alloc: ArenaAllocator,
    entities: Entities,
    // TODO: don't allow it to use the `maxInt(u32)` index.
    groups: Groups,
    shapes: Shapes,

    pub inline fn init() EcsError!Registry {
        var alloc = ArenaAllocator.init(std.heap.page_allocator);
        var self = Registry{
            .alloc = alloc,
            .entities = Entities.init(alloc.allocator()),
            .groups = Groups.init(alloc.allocator()),
            .shapes = Shapes.init(alloc.allocator()),
        };
        _ = try self.getGroup(Shape.fromUnordered(try alloc.allocator().alloc([:0]const u8, 0)));
        return self;
    }

    pub inline fn deinit(self: Registry) void {
        Entities.deinit(self.entities);
        Groups.deinit(self.groups);
        ArenaAllocator.deinit(self.alloc);
    }

    pub fn newEntity(self: *Registry) Entity {
        _ = self;
        return .{ .index = 0, .group = .{ .index = 0 } };
    }

    pub fn addComponent(self: *Registry, entity: Entity, component: anytype) EcsError!void {
        const comp_id: [:0]const u8 = @typeName(@TypeOf(component));

        var shape = entity.shape(self);
        for (shape.components) |it| {
            if (std.mem.eql(u8, it, comp_id)) {
                return EcsError.DuplicateComponent;
            }
        }

        const comp_ix = shape.components.len;
        const slice = self.alloc.allocator().alloc([:0]const u8, comp_ix + 1) catch return EcsError.OutOfMemory;
        std.mem.copyForwards([:0]const u8, slice, shape.components);
        slice[comp_ix] = comp_id;
        shape.components = slice;
        const group = try self.getGroup(shape);
        std.debug.print("{}", .{group});
    }

    fn getGroup(self: *Registry, shape: Shape) EcsError!*Group {
        if (self.shapes.get(shape)) |group| {
            return &self.groups.items[group.index];
        } else {
            const index = @as(u32, @truncate(self.groups.items.len));
            self.groups.append(try Group.create(self.alloc.allocator(), shape)) catch return EcsError.OutOfMemory;
            const group_id = GroupId{ .index = index };
            try self.shapes.put(shape, group_id);
            return self.getGroup(shape);
        }
    }
};

pub const EcsError = error{ DuplicateComponent, OutOfMemory };
