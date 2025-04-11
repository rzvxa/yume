const c = @import("clibs");
const std = @import("std");

const ecs = @import("yume").ecs;
const AssetsDatabase = @import("yume").AssetsDatabase;
const GameApp = @import("yume").GameApp;
const MeshRenderer = @import("yume").MeshRenderer;
const Object = @import("yume").scene_graph.Object;

const Project = @import("../Project.zig");
const Editor = @import("../Editor.zig");

const Self = @This();

pub fn init(_: *GameApp) Self {
    return .{};
}

pub fn deinit(_: *Self) void {}

pub fn draw(self: *Self, ctx: *GameApp) void {
    if (c.ImGui_Begin("Hierarchy", null, 0)) {
        {
            var childs = c.ecs_children(ctx.world.inner, ctx.scene_root);
            while (c.ecs_iter_next(&childs)) {
                for (0..@intCast(childs.count)) |i| {
                    self.drawHierarchyNode(ctx.world, childs.entities[i], 0, ctx);
                }
            }
        }
        const avail = c.ImGui_GetContentRegionAvail();
        _ = c.ImGui_InvisibleButton("outside-the-tree", c.ImVec2{ .x = avail.x, .y = avail.y }, 0);
        if (!drawContextMenu(ctx.scene_root, ctx)) {
            return;
        }
        if (c.ImGui_BeginDragDropTarget()) {
            if (c.ImGui_AcceptDragDropPayload("Object", 0)) |payload| {
                const payload_obj: ?**Object = @ptrCast(@alignCast(payload.*.Data.?));
                if (payload_obj) |p| {
                    _ = p.*.ref();
                    p.*.parent.?.removeChildren(p.*);
                    ctx.scene.root.addChildren(p.*);
                    p.*.deref();
                }
            }
            c.ImGui_EndDragDropTarget();
        }
    }
    c.ImGui_End();
}

fn drawHierarchyNode(self: *Self, world: ecs.World, entity: ecs.Entity, level: usize, ctx: *GameApp) void {
    const name = world.getName(entity);
    var child_it = world.children(entity);
    var has_next = c.ecs_iter_next(&child_it);

    c.ImGui_PushID(name);
    defer c.ImGui_PopID();
    var node_flags = c.ImGuiTreeNodeFlags_OpenOnArrow | c.ImGuiTreeNodeFlags_SpanAvailWidth;
    if (!has_next) {
        node_flags |= c.ImGuiTreeNodeFlags_Leaf;
    }
    if (Editor.instance().selection.contains(.entity, entity)) {
        node_flags |= c.ImGuiTreeNodeFlags_Selected;
    }

    const avail = c.ImGui_GetContentRegionAvail();

    const edge_size = (c.ImGui_GetFrameHeight() + c.ImGui_GetStyle().*.FramePadding.y) / 3;
    const cursor = c.ImGui_GetCursorPos();
    _ = c.ImGui_InvisibleButton("over-drop", c.ImVec2{ .x = avail.x, .y = edge_size }, 0);
    if (c.ImGui_BeginDragDropTarget()) {
        c.ImGui_SetCursorPos(cursor);
        _ = c.ImGui_ColorButtonEx(
            "over-drop-colored",
            c.ImVec4{ .x = 0.1, .y = 0.5, .z = 0.5, .w = 0.8 },
            0,
            c.ImVec2{ .x = avail.x, .y = edge_size },
        );
        if (c.ImGui_AcceptDragDropPayload("Entity", 0)) |payload| {
            const payload_obj: ?*ecs.Entity = @ptrCast(@alignCast(payload.*.Data.?));
            if (payload_obj) |pl| {
                if (pl.* != entity) {
                    const pl_parent = c.ecs_get_parent(ctx.world.inner, pl.*);
                    const ent_parent = c.ecs_get_parent(ctx.world.inner, entity);
                    if (pl_parent == ent_parent) {
                        ctx.world.removePair(pl.*, ecs.relations.ChildOf, pl_parent);
                    }
                    // TODO: change the ordering
                    ctx.world.addPair(pl.*, ecs.relations.ChildOf, ent_parent);
                }
            }
        }
        c.ImGui_EndDragDropTarget();
    }
    c.ImGui_SetCursorPosY(c.ImGui_GetCursorPosY() - edge_size);

    const open = c.ImGui_TreeNodeEx("##", node_flags);
    if (!drawContextMenu(entity, ctx)) {
        if (open) {
            c.ImGui_TreePop();
        }
        return;
    }
    if (c.ImGui_IsItemClicked() and !c.ImGui_IsItemToggledOpen()) {
        Editor.instance().selection = .{ .entity = entity };
    }

    if (c.ImGui_BeginDragDropTarget()) {
        if (c.ImGui_AcceptDragDropPayload("Entity", 0)) |payload| {
            const payload_obj: ?*ecs.Entity = @ptrCast(@alignCast(payload.*.Data.?));
            if (payload_obj) |p| {
                const parent = c.ecs_get_parent(ctx.world.inner, p.*);
                ctx.world.removePair(p.*, ecs.relations.ChildOf, parent);
                ctx.world.addPair(p.*, ecs.relations.ChildOf, entity);
            }
        }
        c.ImGui_EndDragDropTarget();
    }

    if (c.ImGui_BeginDragDropSource(0)) {
        _ = c.ImGui_SetDragDropPayload("Entity", @ptrCast(&entity), @sizeOf(ecs.Entity), c.ImGuiCond_Once);
        c.ImGui_Text(name);
        c.ImGui_EndDragDropSource();
    }

    c.ImGui_SameLine();
    c.ImGui_Image(@intFromPtr(Editor.object_icon_ds), c.ImVec2{ .x = c.ImGui_GetFontSize(), .y = c.ImGui_GetFontSize() });
    c.ImGui_SameLine();
    c.ImGui_Text(name);
    if (open) {
        while (has_next) : (has_next = c.ecs_iter_next(&child_it)) {
            for (0..@intCast(child_it.count)) |i| {
                self.drawHierarchyNode(world, child_it.entities[i], level + 1, ctx);
            }
        }
        c.ImGui_TreePop();
    }
}

fn drawContextMenu(entity: ecs.Entity, ctx: *GameApp) bool {
    var cont = true;
    if (c.ImGui_BeginPopupContextItemEx("context-menu", c.ImGuiPopupFlags_MouseButtonRight)) {
        if (c.ImGui_BeginMenu("New")) {
            if (c.ImGui_MenuItem("Entity")) {
                const new_entity = ctx.world.create("New Entity");
                ctx.world.addPair(new_entity, ecs.relations.ChildOf, entity);
            }
            c.ImGui_Separator();
            if (c.ImGui_MenuItem("Cube")) {
                // FIXME
                // var new_obj = obj.scene.newObject(.{ .parent = obj }) catch @panic("Failed to add new object");
                // new_obj.addComponent(
                //     MeshRenderer,
                //     .{
                //         .mesh = AssetsDatabase.getOrLoadMesh(Project.current().?.getResourceId("builtin://cube.obj") catch @panic("Cube mesh not found")) catch @panic("Failed to load cube mesh"),
                //         .material = AssetsDatabase.getOrLoadMaterial(Project.current().?.getResourceId("builtin://materials/none.mat") catch @panic("None material not found")) catch @panic("Failed to load none material"),
                //     },
                // );
                // new_obj.deref();
            }
            _ = c.ImGui_MenuItem("Sphere*");
            _ = c.ImGui_MenuItem("Plane*");
            c.ImGui_Separator();
            _ = c.ImGui_MenuItem("Camera*");
            c.ImGui_Separator();
            _ = c.ImGui_MenuItem("Directional Light*");
            _ = c.ImGui_MenuItem("Point Light*");
            c.ImGui_EndMenu();
        }
        _ = c.ImGui_MenuItem("Copy*");
        _ = c.ImGui_MenuItem("Paste*");
        if (c.ImGui_MenuItem("Delete")) {
            if (Editor.instance().selection.contains(.entity, entity)) {
                Editor.instance().selection = .none;
            }
            c.ecs_delete(ctx.world.inner, entity);
            cont = false;
        }
        _ = c.ImGui_MenuItem("Rename*");
        _ = c.ImGui_MenuItem("Duplicate*");
        c.ImGui_EndPopup();
    }
    return cont;
}
