const c = @import("clibs");

const std = @import("std");

const Uuid = @import("yume").Uuid;
const Object = @import("yume").Object;
const Component = @import("yume").Component;
const ObjectMetaEditor = @import("object.zig");

const ComponentEditor = struct {
    init: *const fn (allocator: std.mem.Allocator) *anyopaque,
    deinit: *const fn (*anyopaque) void,
    edit: *const fn (self: *anyopaque, obj: *Object, comp: *Component) void,
};

const ComponentEditorInstance = struct { ptr: *anyopaque, type_id: u32 };

const Self = @This();

component_editor_types: std.AutoHashMap(u32, ComponentEditor),
object_meta_editors: std.AutoHashMap(Uuid, ObjectMetaEditor),
component_editors: std.AutoHashMap(Uuid, std.AutoHashMap(Uuid, ComponentEditorInstance)),

pub fn init(allocator: std.mem.Allocator) Self {
    var self = Self{
        .component_editor_types = std.AutoHashMap(u32, ComponentEditor).init(allocator),
        .object_meta_editors = std.AutoHashMap(Uuid, ObjectMetaEditor).init(allocator),
        .component_editors = std.AutoHashMap(Uuid, std.AutoHashMap(Uuid, ComponentEditorInstance)).init(allocator),
    };
    self.component_editor_types.put(42, struct {
        allocator: std.mem.Allocator,
        fn init(a: std.mem.Allocator) *anyopaque {
            const ptr = a.create(@This()) catch @panic("OOM");
            ptr.* = @This(){ .allocator = a };
            return ptr;
        }
        fn deinit(ptr: *anyopaque) void {
            const me = @as(*@This(), @ptrCast(@alignCast(ptr)));
            me.allocator.destroy(me);
        }
        fn edit(_: *anyopaque, obj: *Object, comp: *Component) void {
            c.ImGui_Text("No Editor for %s(compId: %d)", obj.name.ptr, comp.type_id);
        }
        fn asComponentEditor() ComponentEditor {
            return .{
                .init = @This().init,
                .deinit = @This().deinit,
                .edit = @This().edit,
            };
        }
    }.asComponentEditor()) catch @panic("OOM");
    return self;
}

pub fn deinit(self: *Self) void {
    {
        var it = self.object_meta_editors.valueIterator();
        while (it.next()) |next| {
            next.deinit();
        }
    }
    {
        var outer_it = self.component_editors.valueIterator();
        while (outer_it.next()) |outer| {
            var inner_it = outer.valueIterator();
            while (inner_it.next()) |inner| {
                self.componentEditorOf(inner.type_id).deinit(inner.ptr);
            }
            outer.deinit();
        }
    }
    self.component_editor_types.clearAndFree();
    self.component_editors.clearAndFree();
    self.object_meta_editors.clearAndFree();
}

pub fn editObjectMeta(self: *Self, object: *Object) void {
    const entry = self.object_meta_editors.getOrPut(object.uuid) catch @panic("OOM");
    if (!entry.found_existing) {
        entry.value_ptr.* = ObjectMetaEditor.init(self.component_editors.allocator, object);
    }
    entry.value_ptr.edit(object);
}

pub fn editComponent(self: *Self, object: *Object, component: *Component) void {
    const editor = self.componentEditorOf(component.type_id);
    const entry = self.component_editors.getOrPut(object.uuid) catch @panic("OOM");
    if (!entry.found_existing) {
        entry.value_ptr.* = std.AutoHashMap(Uuid, ComponentEditorInstance).init(self.component_editors.allocator);
    }
    const instance = entry.value_ptr.getOrPut(component.uuid) catch @panic("OOM");
    if (!instance.found_existing) {
        instance.value_ptr.* = .{ .ptr = editor.init(self.component_editors.allocator), .type_id = component.type_id };
    }

    editor.edit(instance.value_ptr.*.ptr, object, component);
}

fn componentEditorOf(self: *Self, type_id: u32) ComponentEditor {
    const ty = self.component_editor_types.get(type_id);
    if (ty) |t| {
        return t;
    }

    @panic("no ediitor");
}
