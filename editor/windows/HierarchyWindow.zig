const c = @import("clibs");

const AssetsDatabase = @import("yume").AssetsDatabase;
const GameApp = @import("yume").GameApp;
const MeshRenderer = @import("yume").MeshRenderer;
const Object = @import("yume").scene_graph.Object;

const Project = @import("../Project.zig");
const Editor = @import("../Editor.zig");

const Self = @This();

pub fn draw(self: *Self, ctx: *GameApp) void {
    if (c.ImGui_Begin("Hierarchy", null, 0)) {
        {
            var i: usize = 0;
            while (i < ctx.scene.root.children.items.len) : (i += 1) {
                self.drawHierarchyNode(ctx.scene.root.children.items[i]);
            }
        }
        const avail = c.ImGui_GetContentRegionAvail();
        _ = c.ImGui_InvisibleButton("outside-the-tree", c.ImVec2{ .x = avail.x, .y = avail.y }, 0);
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
        }
        _ = c.ImGui_MenuItem("Rename*");
        _ = c.ImGui_MenuItem("Duplicate*");
        c.ImGui_EndPopup();
    }
}
