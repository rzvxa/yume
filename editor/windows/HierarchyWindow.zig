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

query: *ecs.Query,

pub fn init(ctx: *GameApp) Self {
    var desc = ecs.QueryDesc{};
    desc.terms[0] = .{ .id = ecs.pair(ecs.relations.ChildOf, ecs.core.Wildcard), .oper = ecs.operators.Not };
    desc.terms[1] = .{ .id = ecs.core.System, .oper = ecs.operators.Not };
    desc.terms[2] = .{ .id = ecs.core.Component, .oper = ecs.operators.Not };
    desc.terms[3] = .{ .id = ecs.scopes.Flecs, .oper = ecs.operators.Not };
    desc.terms[4] = .{ .id = ecs.scopes.FlecsCore, .oper = ecs.operators.Not };
    desc.terms[5] = .{ .id = ecs.scopes.Module, .oper = ecs.operators.Not };

    return .{
        .query = ctx.world.query(&desc),
    };
}

pub fn deinit(self: *Self) void {
    c.ecs_query_fini(self.query);
}

// Function to recursively print the hierarchy
fn print_hierarchy(world: *c.ecs_world_t, entity: c.ecs_entity_t, level: usize) void {
    const name = c.ecs_get_name(world, entity);
    if (name != null) {
        for (0..level) |_| {
            std.debug.print("  ", .{});
        }
        std.debug.print("{s}\n", .{name});
    }

    // Iterate over the entity's children
    // var it = c.ecs_children(world, entity);
    // while (c.ecs_iter_next(&it)) {
    // for (0..@intCast(it.count)) |i| {
    // print_hierarchy(world, it.entities[i], level + 1);
    // }
    // }
}

pub fn draw(self: *Self, ctx: *GameApp) void {
    if (c.ImGui_Begin("Hierarchy", null, 0)) {
        {
            var iter = c.ecs_query_iter(ctx.world.inner, self.query);
            // defer c.ecs_iter_fini(&iter);
            while (c.ecs_iter_next(&iter)) {
                for (0..@intCast(iter.count)) |i| {
                    print_hierarchy(ctx.world.inner, iter.entities[i], 0);
                }
            }
            var i: usize = 0;
            while (i < ctx.scene.root.children.items.len) : (i += 1) {
                self.drawHierarchyNode(ctx.scene.root.children.items[i]);
            }
        }
        const avail = c.ImGui_GetContentRegionAvail();
        _ = c.ImGui_InvisibleButton("outside-the-tree", c.ImVec2{ .x = avail.x, .y = avail.y }, 0);
        if (!drawContextMenu(ctx.scene.root)) {
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

fn drawHierarchyNode(self: *Self, obj: *Object) void {
    c.ImGui_PushID(obj.name.ptr);
    defer c.ImGui_PopID();
    var node_flags = c.ImGuiTreeNodeFlags_OpenOnArrow | c.ImGuiTreeNodeFlags_SpanAvailWidth;
    if (obj.children.items.len == 0) {
        node_flags |= c.ImGuiTreeNodeFlags_Leaf;
    }
    if (Editor.instance().selection == obj) {
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
        if (c.ImGui_AcceptDragDropPayload("Object", 0)) |payload| {
            const payload_obj: ?**Object = @ptrCast(@alignCast(payload.*.Data.?));
            if (payload_obj) |pl| {
                if (pl.* != obj) {
                    const pl_parent = pl.*.parent.?;
                    const obj_parent = obj.*.parent.?;
                    if (pl_parent == obj_parent) {
                        pl_parent.removeChildren(pl.*);
                    }
                    const obj_idx = obj_parent.findChildren(obj).?;
                    obj_parent.insertChildren(obj_idx, pl.*);
                }
            }
        }
        c.ImGui_EndDragDropTarget();
    }
    c.ImGui_SetCursorPosY(c.ImGui_GetCursorPosY() - edge_size);

    const open = c.ImGui_TreeNodeEx("##", node_flags);
    if (!drawContextMenu(obj)) {
        if (open) {
            c.ImGui_TreePop();
        }
        return;
    }
    if (c.ImGui_IsItemClicked() and !c.ImGui_IsItemToggledOpen()) {
        Editor.instance().selection = obj;
    }

    if (c.ImGui_BeginDragDropTarget()) {
        if (c.ImGui_AcceptDragDropPayload("Object", 0)) |payload| {
            const payload_obj: ?**Object = @ptrCast(@alignCast(payload.*.Data.?));
            if (payload_obj) |p| {
                _ = p.*.ref();
                p.*.parent.?.removeChildren(p.*);
                obj.addChildren(p.*);
                p.*.deref();
            }
        }
        c.ImGui_EndDragDropTarget();
    }

    if (c.ImGui_BeginDragDropSource(0)) {
        _ = c.ImGui_SetDragDropPayload("Object", @ptrCast(&obj), @sizeOf(*Object), c.ImGuiCond_Once);
        c.ImGui_Text(obj.name.ptr);
        c.ImGui_EndDragDropSource();
    }

    c.ImGui_SameLine();
    c.ImGui_Image(@intFromPtr(Editor.object_icon_ds), c.ImVec2{ .x = c.ImGui_GetFontSize(), .y = c.ImGui_GetFontSize() });
    c.ImGui_SameLine();
    c.ImGui_Text(obj.name.ptr);
    if (open) {
        var i: usize = 0;
        while (i < obj.children.items.len) : (i += 1) {
            self.drawHierarchyNode(obj.children.items[i]);
        }
        c.ImGui_TreePop();
    }
}

fn drawContextMenu(obj: *Object) bool {
    var cont = true;
    if (c.ImGui_BeginPopupContextItemEx("context-menu", c.ImGuiPopupFlags_MouseButtonRight)) {
        if (c.ImGui_BeginMenu("New")) {
            if (c.ImGui_MenuItem("Object")) {
                var new_obj = obj.scene.newObject(.{ .parent = obj }) catch @panic("Failed to add new object");
                new_obj.deref();
            }
            c.ImGui_Separator();
            if (c.ImGui_MenuItem("Cube")) {
                var new_obj = obj.scene.newObject(.{ .parent = obj }) catch @panic("Failed to add new object");
                new_obj.addComponent(
                    MeshRenderer,
                    .{
                        .mesh = AssetsDatabase.getOrLoadMesh(Project.current().?.getResourceId("builtin://cube.obj") catch @panic("Cube mesh not found")) catch @panic("Failed to load cube mesh"),
                        .material = AssetsDatabase.getOrLoadMaterial(Project.current().?.getResourceId("builtin://materials/none.mat") catch @panic("None material not found")) catch @panic("Failed to load none material"),
                    },
                );
                new_obj.deref();
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
            if (Editor.instance().selection != null and Editor.instance().selection.? == obj) {
                Editor.instance().selection = null;
            }
            obj.parent.?.removeChildren(obj);
            cont = false;
        }
        _ = c.ImGui_MenuItem("Rename*");
        _ = c.ImGui_MenuItem("Duplicate*");
        c.ImGui_EndPopup();
    }
    return cont;
}

// void iterate_tree(ecs_world_t *ecs, ecs_entity_t e, Position p_parent) {
//     // Print hierarchical name of entity & the entity type
//     char *path_str = ecs_get_path(ecs, e);
//     char *type_str = ecs_type_str(ecs, ecs_get_type(ecs, e));
//     printf("%s [%s]\n", path_str, type_str);
//     ecs_os_free(type_str);
//     ecs_os_free(path_str);
//
//     // Get entity position
//     const Position *ptr = ecs_get(ecs, e, Position);
//
//     // Calculate actual position
//     Position p_actual = {ptr->x + p_parent.x, ptr->y + p_parent.y};
//     printf("{%f, %f}\n\n", p_actual.x, p_actual.y);
//
//     // Iterate children recursively
//     ecs_iter_t it = ecs_children(ecs, e);
//     while (ecs_children_next(&it)) {
//         for (int i = 0; i < it.count; i ++) {
//             iterate_tree(ecs, it.entities[i], p_actual);
//         }
//     }
// }
