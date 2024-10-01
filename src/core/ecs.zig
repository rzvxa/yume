// Parts of this file contains code that are either copied or inspired from [zecsi]<https://github.com/ryupold/zecsi> project.
//
const std = @import("std");
const Allocator = std.mem.Allocator;

const TypeId = @import("TypeId.zig");
const collections = @import("../root.zig").collections;
const IndexMap = collections.IndexMap;
const List = collections.List;

const Entities = List(Entity);
const Tables = IndexMap(TableId, Table);

const Shapes = std.HashMap(Shape, TableId, ShapeHashContext, std.hash_map.default_max_load_percentage);

const RowIndex = u32;

/// Don't initialize or modify it manually.
pub const Entity = struct {
    table: TableId,
    index: RowIndex,

    /// Does this entity have any components?
    pub inline fn isEmpty(self: Entity) bool {
        return self.table.index == 0;
    }

    pub inline fn shape(self: Entity, reg: *const Registry) *const Shape {
        const table = reg.tables.items[self.table.index];
        return &table.shape;
    }
};

/// Don't initialize or modify it manually.
pub const TableId = struct {
    index: u32,
};

pub const Column = struct {
    /// `TypeId` of elements of this column
    type_id: TypeId,
    allocator: Allocator,
    raw: *anyopaque,
    vtable: struct {
        deinit: *const fn (self: *Column) void,
        cloneEmpty: *const fn (self: *const Column) EcsError!Column,
    },

    fn init(allocator: Allocator, comptime T: type) EcsError!Column {
        const ptr = allocator.create(List(T)) catch return EcsError.OutOfMemory;
        ptr.* = List(T).init(allocator);
        return Column{
            .type_id = TypeId.new(T),
            .allocator = allocator,
            .raw = @as(*anyopaque, @ptrCast(ptr)),
            .vtable = .{
                .deinit = &(struct {
                    fn deinit(self: *Column) void {
                        const list = self.asList(T) catch unreachable;
                        list.deinit();
                    }
                }).deinit,
                .cloneEmpty = &(struct {
                    fn cloneEmpty(self: *const Column) EcsError!Column {
                        return Column.init(self.allocator, T);
                    }
                }).cloneEmpty,
            },
        };
    }

    inline fn deinit(self: *Column) void {
        self.vtable.deinit(self);
    }

    inline fn cloneEmpty(self: *const Column) EcsError!Column {
        return self.vtable.cloneEmpty(self);
    }

    fn asList(self: *Column, comptime T: type) EcsError!*List(T) {
        if (!TypeId.new(T).eql(self.type_id)) return EcsError.InvalidComponent;
        return @as(*List(T), @ptrCast(@alignCast(self.raw)));
    }
};

/// Don't initialize or modify it manually.
pub const Table = struct {
    allocator: Allocator,
    shape: Shape,
    columns: []Column,
    unused_rows: List(RowIndex),

    fn initEmpty(allocator: Allocator) EcsError!Table {
        return .{
            .allocator = allocator,
            .shape = Shape.init(List(TypeId).init(allocator)),
            .columns = allocator.alloc(Column, 0) catch return EcsError.OutOfMemory,
            .unused_rows = List(RowIndex).init(allocator),
        };
    }

    fn cloneTableShapeWithExtraColumn(self: *Table, comptime T: type) EcsError!Table {
        const type_id = TypeId.new(T);

        var shape = try self.shape.clone();
        shape.components.append(type_id) catch return EcsError.OutOfMemory;
        std.mem.sort(TypeId, shape.components.items, {}, TypeId.sort);
        // TODO: sort columns
        const columns = self.allocator.alloc(Column, self.columns.len + 1) catch return EcsError.OutOfMemory;
        for (self.columns, 0..) |col, i| {
            columns[i] = try col.cloneEmpty();
        }
        columns[self.columns.len] = try Column.init(self.allocator, T);

        return .{
            .allocator = self.allocator,
            .shape = shape,
            .columns = columns,
            .unused_rows = List(RowIndex).init(self.allocator),
        };
    }

    fn deinit(self: Table, allocator: Allocator) void {
        for (self.columns) |col| {
            col.deinit();
        }
        allocator.free(self.columns);
        self.unused_rows.deinit();
    }

    fn addRow(self: *Table, fields: []anyopaque) EcsError!RowIndex {
        if (self.columns.items.len != fields.len) {
            return EcsError.InvalidShape;
        }
        if (self.columns.items.len == 0) {
            return 0;
        }
        for (self.columns.items, fields) |column, field| {
            column.append(field);
        }
        return @as(u32, @truncate(self.columns[0].items.len));
    }

    fn removeRow(self: *Table, row: RowIndex) ?[]anyopaque {
        if (self.columns.items.len == 0) {
            return null;
        }

        _ = row;
        // TODO
        return null;
        // if (self.columns[0].init)
    }
};

/// Don't initialize these manually, Only use the static methods to construct one otherwise you might endup with unsound code.
const Shape = struct {
    components: List(TypeId),

    fn init(components: List(TypeId)) Shape {
        const self = Shape{ .components = components };
        std.mem.sort(TypeId, self.components.items, {}, TypeId.sort);
        return self;
    }

    fn deinit(self: Shape) void {
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
    tables: Tables,
    shapes: Shapes,

    pub inline fn init(allocator: Allocator) EcsError!Registry {
        var self = Registry{
            .allocator = allocator,
            .entities = Entities.init(allocator),
            .tables = try Tables.initCapacity(allocator, 1),
            .shapes = Shapes.init(allocator),
        };
        const unit_table = try Table.initEmpty(allocator);
        _ = try self.addTable(unit_table);
        return self;
    }

    pub inline fn deinit(self: Registry) void {
        Entities.deinit(self.entities);
        Tables.deinit(self.tables);
    }

    pub fn newEntity(self: *Registry) Entity {
        _ = self;
        return .{ .index = 0, .table = .{ .index = 0 } };
    }

    pub fn addComponent(self: *Registry, entity: Entity, comptime TComponent: type, component: TComponent) EcsError!void {
        _ = component;
        const comp_id = TypeId.new(TComponent);

        const old_shape = entity.shape(self);
        for (old_shape.components.items) |it| {
            if (it.eql(comp_id)) {
                return EcsError.DuplicateComponent;
            }
        }

        var new_shape = try old_shape.clone();
        new_shape.components.append(comp_id) catch return EcsError.OutOfMemory;
        const old_table = &self.tables.items[entity.table.index];
        const new_table = self.getTable(new_shape) orelse try self.newTable(old_table, TComponent);
        std.debug.print("old_len: {}; new_len: {}", .{ old_table.shape.components.items.len, new_table.shape.components.items.len });
    }

    fn getTable(self: *Registry, shape: Shape) ?*Table {
        if (self.shapes.get(shape)) |table| {
            // if table already exists we don't need our input shape anymore.
            shape.deinit();
            return &self.tables.items[table.index];
        } else {
            return null;
        }
    }

    /// Create and append a new table based on the `base` table's shape, With the addition of `new_column`
    fn newTable(self: *Registry, base: *Table, comptime new_column: type) EcsError!*Table {
        const table = try base.cloneTableShapeWithExtraColumn(new_column);
        const index = (try self.addTable(table)).index;
        return &self.tables.items[index];
    }

    fn addTable(self: *Registry, table: Table) EcsError!TableId {
        if (self.shapes.contains(table.shape)) {
            return EcsError.InvalidShape;
        }

        const index = @as(u32, @truncate(self.tables.items.len));
        self.tables.append(table) catch return EcsError.OutOfMemory;
        const table_id = TableId{ .index = index };
        try self.shapes.put(table.shape, table_id);

        return table_id;
    }
};

pub const EcsError = error{ DuplicateComponent, InvalidShape, InvalidComponent, OutOfMemory };
