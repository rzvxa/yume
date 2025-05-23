const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;

const GameApp = @import("yume").GameApp;
const Uuid = @import("yume").Uuid;
const MeshRenderer = @import("yume").MeshRenderer;
const EntityMetaEditor = @import("entity.zig");
const ObjectTransformEditor = @import("transform.zig");
const MeshEditor = @import("MeshEditor.zig");
const MaterialEditor = @import("MaterialEditor.zig");
const DirectionalLightEditor = @import("DirectionalLightEditor.zig");
const PointLightEditor = @import("PointLightEditor.zig");
const CameraEditor = @import("CameraEditor.zig");
const Editor = @import("../Editor.zig");

const imutils = @import("../imutils.zig");

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
    edit: *const fn (self: *anyopaque, comp_id: ecs.Entity, comp: ecs.Entity, ctx: *GameApp) void,
    gizmo: *const fn (self: *anyopaque, comp_id: ecs.Entity, comp: ecs.Entity, ctx: *GameApp) void = &struct {
        fn f(_: *anyopaque, _: ecs.Entity, _: ecs.Entity, _: *GameApp) void {}
    }.f,
    flags: ComponentEditorFlags = .{},
};

const ComponentEditorInstance = struct { ptr: *anyopaque, type_id: ecs.TypeId };

const Self = @This();

component_editor_types: std.AutoHashMap(ecs.TypeId, ComponentEditor),
entity_meta_editors: std.AutoHashMap(ecs.Entity, EntityMetaEditor),
entity_transform_editors: std.AutoHashMap(ecs.Entity, ObjectTransformEditor),
component_editors: std.AutoHashMap(ecs.Entity, std.AutoHashMap(ecs.Entity, ComponentEditorInstance)),

pub fn init(allocator: std.mem.Allocator) Self {
    var self = Self{
        .component_editor_types = std.AutoHashMap(ecs.TypeId, ComponentEditor).init(allocator),
        .entity_meta_editors = std.AutoHashMap(ecs.Entity, EntityMetaEditor).init(allocator),
        .entity_transform_editors = std.AutoHashMap(ecs.Entity, ObjectTransformEditor).init(allocator),
        .component_editors = std.AutoHashMap(ecs.Entity, std.AutoHashMap(ecs.Entity, ComponentEditorInstance)).init(allocator),
    };
    self.registerBuiltinComponentEditors();
    return self;
}

pub fn deinit(self: *Self) void {
    {
        var it = self.entity_meta_editors.valueIterator();
        while (it.next()) |next| {
            next.deinit();
        }
    }
    {
        var it = self.entity_transform_editors.valueIterator();
        while (it.next()) |next| {
            next.deinit();
        }
    }
    {
        var outer_it = self.component_editors.valueIterator();
        while (outer_it.next()) |outer| {
            var inner_it = outer.valueIterator();
            while (inner_it.next()) |inner| {
                self.componentEditorOf(inner.type_id).?.deinit(inner.ptr);
            }
            outer.deinit();
        }
    }
    self.component_editor_types.clearAndFree();
    self.component_editors.clearAndFree();
    self.entity_meta_editors.clearAndFree();
    self.entity_transform_editors.clearAndFree();
}

pub fn editEntityMeta(self: *Self, entity: ecs.Entity, ctx: *GameApp) void {
    const entry = self.entity_meta_editors.getOrPut(entity) catch @panic("OOM");
    if (!entry.found_existing) {
        entry.value_ptr.* = EntityMetaEditor.init(self.component_editors.allocator, entity, ctx);
    }
    entry.value_ptr.edit(entity, ctx);
}

pub fn editEntityTransform(self: *Self, entity: ecs.Entity, ctx: *GameApp) void {
    const entry = self.entity_transform_editors.getOrPut(entity) catch @panic("OOM");
    if (!entry.found_existing) {
        entry.value_ptr.* = ObjectTransformEditor.init(self.component_editors.allocator, entity);
    }
    entry.value_ptr.edit(entity, ctx);
}

pub fn editComponent(self: *Self, editor: ComponentEditor, entity: ecs.Entity, component: ecs.Entity, ctx: *GameApp) void {
    const entry = self.component_editors.getOrPut(entity) catch @panic("OOM");
    if (!entry.found_existing) {
        entry.value_ptr.* = std.AutoHashMap(ecs.Entity, ComponentEditorInstance).init(self.component_editors.allocator);
    }
    const instance = entry.value_ptr.getOrPut(component) catch @panic("OOM");
    if (!instance.found_existing) {
        instance.value_ptr.* = .{ .ptr = editor.init(self.component_editors.allocator), .type_id = component };
    }

    const name = ctx.world.getName(component);
    var enable = c.ecs_is_enabled_id(ctx.world.inner, entity, component);

    var open: bool = undefined;
    if (editor.flags.no_disable) {
        open = c.ImGui_CollapsingHeader(name, c.ImGuiTreeNodeFlags_DefaultOpen);
    } else {
        open = imutils.collapsingHeaderWithCheckBox(name, &enable, c.ImGuiTreeNodeFlags_DefaultOpen);
    }
    if (open) {
        editor.edit(instance.value_ptr.*.ptr, entity, component, ctx);
    }
}

pub fn componentEditorOf(self: *Self, type_id: ecs.Entity) ?ComponentEditor {
    const ty = self.component_editor_types.get(type_id);
    if (ty) |t| {
        return t;
    }

    return null;
}

pub fn onDrawGizmos(self: *Self) void {
    switch (Editor.instance().selection) {
        .entity => |entity| {
            const typ = c.ecs_get_type(Editor.instance().ctx.world.inner, entity);
            const editor = Editor.instance();

            for (0..@intCast(typ[0].count)) |i| {
                const id: c.ecs_id_t = typ[0].array[i];
                if (id & c.ECS_PAIR > 0) {
                    continue;
                }
                const comp = id & c.ECS_COMPONENT_MASK;

                const type_id = c.ecs_get_typeid(Editor.instance().ctx.world.inner, comp);
                const ed = editor.editors.componentEditorOf(type_id) orelse continue;
                if (self.component_editors.get(entity)) |components| {
                    if (components.get(comp)) |it| {
                        ed.gizmo(it.ptr, entity, it.type_id, Editor.instance().ctx);
                    }
                }
            }
        },
        else => {},
    }
}

fn registerBuiltinComponentEditors(self: *Self) void {
    self.component_editor_types.put(ecs.typeId(ecs.components.Camera), CameraEditor.asComponentEditor()) catch @panic("OOM");
    self.component_editor_types.put(ecs.typeId(ecs.components.DirectionalLight), DirectionalLightEditor.asComponentEditor()) catch @panic("OOM");
    self.component_editor_types.put(ecs.typeId(ecs.components.PointLight), PointLightEditor.asComponentEditor()) catch @panic("OOM");
    self.component_editor_types.put(ecs.typeId(ecs.components.Mesh), MeshEditor.asComponentEditor()) catch @panic("OOM");
    self.component_editor_types.put(ecs.typeId(ecs.components.Material), MaterialEditor.asComponentEditor()) catch @panic("OOM");
}
