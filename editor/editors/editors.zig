const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const components = @import("yume").components;

const GameApp = @import("yume").GameApp;
const Uuid = @import("yume").Uuid;
const Object = @import("yume").Object;
const Component = @import("yume").Component;
const Camera = @import("yume").Camera;
const MeshRenderer = @import("yume").MeshRenderer;
const TypeId = @import("yume").TypeId;
const typeId = @import("yume").typeId;
const ObjectMetaEditor = @import("object.zig");
const ObjectTransformEditor = @import("transform.zig");
const MeshRendererEditor = @import("MeshRendererEditor.zig");
const CameraEditor = @import("CameraEditor.zig");

pub const ComponentEditorFlags = packed struct {
    no_disable: bool = false,
    _padding1: bool = false,
    _padding2: bool = false,
    _padding3: bool = false,
    _padding4: bool = false,
    _padding5: bool = false,
    _padding6: bool = false,
    _padding7: bool = false,
};

pub const ComponentEditor = struct {
    init: *const fn (allocator: std.mem.Allocator) *anyopaque,
    deinit: *const fn (*anyopaque) void,
    edit: *const fn (self: *anyopaque, obj: *Object, comp: *Component) void,
    flags: ComponentEditorFlags = .{},
};

const ComponentEditorInstance = struct { ptr: *anyopaque, type_id: TypeId };

const Self = @This();

component_editor_types: std.AutoHashMap(TypeId, ComponentEditor),
object_meta_editors: std.AutoHashMap(ecs.Entity, ObjectMetaEditor),
object_transform_editors: std.AutoHashMap(ecs.Entity, ObjectTransformEditor),
component_editors: std.AutoHashMap(Uuid, std.AutoHashMap(Uuid, ComponentEditorInstance)),

pub fn init(allocator: std.mem.Allocator) Self {
    var self = Self{
        .component_editor_types = std.AutoHashMap(TypeId, ComponentEditor).init(allocator),
        .object_meta_editors = std.AutoHashMap(ecs.Entity, ObjectMetaEditor).init(allocator),
        .object_transform_editors = std.AutoHashMap(ecs.Entity, ObjectTransformEditor).init(allocator),
        .component_editors = std.AutoHashMap(Uuid, std.AutoHashMap(Uuid, ComponentEditorInstance)).init(allocator),
    };
    self.registerBuiltinComponentEditors();
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
        var it = self.object_transform_editors.valueIterator();
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
    self.object_transform_editors.clearAndFree();
}

pub fn editEntityMeta(self: *Self, entity: ecs.Entity, ctx: *GameApp) void {
    const entry = self.object_meta_editors.getOrPut(entity) catch @panic("OOM");
    if (!entry.found_existing) {
        entry.value_ptr.* = ObjectMetaEditor.init(self.component_editors.allocator, entity, ctx);
    }
    entry.value_ptr.edit(entity, ctx);
}

pub fn editEntityTransform(self: *Self, entity: ecs.Entity, ctx: *GameApp) void {
    const entry = self.object_transform_editors.getOrPut(entity) catch @panic("OOM");
    if (!entry.found_existing) {
        entry.value_ptr.* = ObjectTransformEditor.init(self.component_editors.allocator, entity);
    }
    if (collapsingHeaderWithCheckBox("Transform", null, c.ImGuiTreeNodeFlags_DefaultOpen)) {
        entry.value_ptr.edit(entity, ctx);
    }
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

    var open: bool = undefined;
    if (editor.flags.no_disable) {
        open = c.ImGui_CollapsingHeader(component.name, c.ImGuiTreeNodeFlags_DefaultOpen);
    } else {
        open = collapsingHeaderWithCheckBox(component.name, &component.enable, c.ImGuiTreeNodeFlags_DefaultOpen);
    }
    if (open) {
        editor.edit(instance.value_ptr.*.ptr, object, component);
    }
}

fn componentEditorOf(self: *Self, type_id: TypeId) ComponentEditor {
    const ty = self.component_editor_types.get(type_id);
    if (ty) |t| {
        return t;
    }

    return struct {
        allocator: std.mem.Allocator,
        pub fn init(a: std.mem.Allocator) *anyopaque {
            const ptr = a.create(@This()) catch @panic("OOM");
            ptr.* = @This(){ .allocator = a };
            return ptr;
        }

        pub fn deinit(ptr: *anyopaque) void {
            const me = @as(*@This(), @ptrCast(@alignCast(ptr)));
            me.allocator.destroy(me);
        }

        pub fn edit(_: *anyopaque, obj: *Object, comp: *Component) void {
            c.ImGui_Text("No Editor for %s{ compId: %d, uuid: %s }", obj.name.ptr, comp.type_id, &comp.uuid.urnZ());
        }

        pub fn asComponentEditor() ComponentEditor {
            return .{
                .init = @This().init,
                .deinit = @This().deinit,
                .edit = @This().edit,
            };
        }
    }.asComponentEditor();
}

fn registerBuiltinComponentEditors(self: *Self) void {
    self.component_editor_types.put(typeId(MeshRenderer), MeshRendererEditor.asComponentEditor()) catch @panic("OOM");
    self.component_editor_types.put(typeId(Camera), CameraEditor.asComponentEditor()) catch @panic("OOM");
}

fn collapsingHeaderWithCheckBox(label: [*c]const u8, checked: [*c]bool, flags: c.ImGuiTreeNodeFlags) bool {
    if (checked != null) {
        _ = c.ImGui_Checkbox("###enable", checked);
        const x = c.ImGui_GetCursorPosX();
        const style = c.ImGui_GetStyle();
        c.ImGui_SameLineEx(x + c.ImGui_GetFrameHeight() + style.*.ItemInnerSpacing.x - 1, 0);
    }
    return c.ImGui_CollapsingHeader(label, flags);
}
