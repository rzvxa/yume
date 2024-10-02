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
        move: *const fn (from: *Column, to: *Column, row: RowIndex) EcsError!void,
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
                .move = &(struct {
                    fn move(from: *Column, to: *Column, row: RowIndex) EcsError!void {
                        const from_list = try from.asList(T);
                        const to_list = try to.asList(T);
                        const field = from_list.items[row];
                        to_list.append(field) catch return EcsError.OutOfMemory;
                        from_list.items[row] = undefined;
                    }
                }).move,
            },
        };
    }

    inline fn deinit(self: *Column) void {
        self.vtable.deinit(self);
    }

    inline fn cloneEmpty(self: *const Column) EcsError!Column {
        return self.vtable.cloneEmpty(self);
    }

    inline fn move(from: *Column, to: *Column, row: RowIndex) EcsError!void {
        return from.vtable.move(from, to, row);
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

    fn cloneTableShapeWithExtraColumn(self: *const Table, comptime T: type) EcsError!struct {
        table: Table,
        match_indexed: []?u32,
    } {
        const type_id = TypeId.new(T);

        var shape = try self.shape.clone();
        shape.components.append(type_id) catch return EcsError.OutOfMemory;
        std.mem.sort(TypeId, shape.components.items, {}, TypeId.sort);
        const match_indexed = try self.matchIndexed(&shape);

        const columns = self.allocator.alloc(Column, shape.components.items.len) catch return EcsError.OutOfMemory;
        for (match_indexed, 0..) |match, col| {
            if (match) |other| {
                columns[col] = try self.columns[other].cloneEmpty();
            } else {
                columns[col] = try Column.init(self.allocator, T);
            }
        }

        return .{
            .table = .{
                .allocator = self.allocator,
                .shape = shape,
                .columns = columns,
                .unused_rows = List(RowIndex).init(self.allocator),
            },
            .match_indexed = match_indexed,
        };
    }

    fn deinit(self: Table) void {
        for (self.columns) |col| {
            col.deinit();
        }
        self.allocator.free(self.columns);
        self.unused_rows.deinit();
    }

    /// allocates an slice using the allocator of this table
    /// caller is the owner of slice
    fn matchIndexed(self: *const Table, shape: *const Shape) EcsError![]?u32 {
        var result = self.allocator.alloc(?u32, shape.components.items.len) catch return EcsError.OutOfMemory;
        for (shape.components.items, 0..) |needle, i| {
            result[i] = null;
            for (self.shape.components.items, 0..) |it, column_ix| {
                if (it.eql(needle)) {
                    result[i] = @as(u32, @truncate(column_ix));
                    break;
                }
            }
        }
        return result;
    }

    // fn addRow(self: *Table, fields: []anyopaque) EcsError!RowIndex {
    //     if (self.columns.items.len != fields.len) {
    //         return EcsError.InvalidShape;
    //     }
    //     if (self.columns.items.len == 0) {
    //         return 0;
    //     }
    //     for (self.columns.items, fields) |column, field| {
    //         column.append(field);
    //     }
    //     return @as(u32, @truncate(self.columns[0].items.len));
    // }

    // Moves fields at the `row` from the `from` table to the `to` leaving behind `undefined` in their place.
    fn moveRow(from: *Table, to: *Table, row: RowIndex, skip_unpresent_columns: bool, match_indexed: ?[]?u32) EcsError!void {
        const ensured_match_indexed = match_indexed orelse try from.matchIndexed(&to.shape);
        defer if (match_indexed) |_| {
            from.allocator.free(ensured_match_indexed);
        };

        for (ensured_match_indexed, 0..) |match, col| {
            if (match) |mapping| {
                try from.columns[mapping].move(&to.columns[col], row);
            } else if (!skip_unpresent_columns) {
                return EcsError.InvalidShape;
            }
        }
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

    pub fn addComponent(self: *Registry, entity: *Entity, comptime TComponent: type, component: TComponent) EcsError!void {
        const comp_id = TypeId.new(TComponent);

        const old_shape = entity.shape(self);
        for (old_shape.components.items) |it| {
            if (it.eql(comp_id)) {
                return EcsError.DuplicateComponent;
            }
        }

        var new_shape = try old_shape.clone();
        defer new_shape.deinit();
        new_shape.components.append(comp_id) catch return EcsError.OutOfMemory;
        var new_table_id: TableId = undefined;
        var maybe_match_indexed: ?[]?u32 = null;

        if (self.shapes.get(new_shape)) |id| {
            new_table_id = id;
        } else {
            const result = try self.newTable(entity.table, TComponent);
            new_table_id = result.id;
            maybe_match_indexed = result.match_indexed;
        }
        const new_table = self.getTable(new_table_id);
        const old_table = self.getTable(entity.table);
        const match_indexed = maybe_match_indexed orelse try old_table.matchIndexed(&new_table.shape);
        defer self.allocator.free(match_indexed);
        try Table.moveRow(old_table, new_table, entity.index, true, match_indexed);
        for (match_indexed, 0..) |match, col| {
            if (match == null) {
                (try new_table.columns[col].asList(TComponent)).append(component) catch return EcsError.OutOfMemory;
            }
        }
    }

    pub fn view(self: *Registry, comptime query: anytype) View(query) {
        return View(query){
            .registry = self,
        };
    }

    fn getTable(self: *Registry, table_id: TableId) *Table {
        return &self.tables.items[table_id.index];
    }

    /// Create and append a new table based on the `base` table's shape, With the addition of `new_column`
    fn newTable(self: *Registry, base: TableId, comptime new_column: type) EcsError!struct { id: TableId, match_indexed: []?u32 } {
        const result = try self.getTable(base).cloneTableShapeWithExtraColumn(new_column);
        const table_id = try self.addTable(result.table);
        return .{ .id = table_id, .match_indexed = result.match_indexed };
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

fn View(comptime query: anytype) type {
    _ = query;
    const fields: [1]std.builtin.Type.StructField = .{.{
        .name = "registry",
        .type = *Registry,
        .default_value = null,
        .is_comptime = false,
        .alignment = @alignOf(*Registry),
    }};
    return @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub const EcsError = error{
    DuplicateComponent,
    InvalidShape,
    InvalidEntity,
    InvalidComponent,
    OutOfMemory,
};
