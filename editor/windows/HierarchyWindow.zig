const c = @import("clibs");
const std = @import("std");

const ecs = @import("yume").ecs;
const Assets = @import("yume").Assets;
const GameApp = @import("yume").GameApp;
const Vec3 = @import("yume").Vec3;

const AssetsDatabase = @import("../AssetsDatabase.zig");

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
            const childs = ctx.world.childrenSorted(ctx.scene_root, ctx.allocator) catch @panic("Failed to retrieve sorted children");
            defer ctx.allocator.free(childs);
            for (childs) |child| {
                self.drawHierarchyNode(ctx.world, child, 0, ctx) catch @panic("Failed to draw node");
            }
        }
        const avail = noZero(c.ImGui_GetContentRegionAvail());
        const cursor = c.ImGui_GetCursorPos();
        _ = c.ImGui_InvisibleButton("outside-the-tree", c.ImVec2{ .x = avail.x, .y = avail.y }, 0);
        if (!(drawContextMenu(ctx.scene_root, ctx) catch @panic("failed to draw context menu"))) {
            return;
        }
        if (c.ImGui_BeginDragDropTarget()) {
            c.ImGui_SetCursorPos(cursor);
            const edge_size = (c.ImGui_GetFrameHeight() + c.ImGui_GetStyle().*.FramePadding.y) / 3;
            _ = c.ImGui_ColorButtonEx(
                "outside-the-tree-edge-colored",
                c.ImVec4{ .x = 0.1, .y = 0.5, .z = 0.5, .w = 0.8 },
                0,
                c.ImVec2{ .x = avail.x, .y = edge_size },
            );
            if (c.ImGui_AcceptDragDropPayload("Entity", 0)) |payload| { // drop in root
                const payload_obj: ?*ecs.Entity = @ptrCast(@alignCast(payload.*.Data.?));
                if (payload_obj) |p| {
                    Editor.trySetParentKeepUniquePathName(ctx.world, p.*, ctx.scene_root, ctx.allocator) catch |err| switch (err) {
                        error.CyclicRelation => _ = Editor.messageBox(.{
                            .title = "Error!",
                            .message = "Invalid Cyclic Relationship!",
                            .kind = .err,
                            .buttons = &[1]c.SDL_MessageBoxButtonData{
                                .{ .buttonID = 0, .text = "Ok" },
                            },
                        }) catch @panic("Failed to set parent of entity to root"),
                        error.Cancel => {},
                        else => @panic("Failed to set parent of entity to root"),
                    };
                    ctx.world.changeEntityOrder(p.*, std.math.maxInt(u32), ctx.allocator) catch @panic("Failed to set parent of entity to root");
                }
            }
            c.ImGui_EndDragDropTarget();
        }
    }
    c.ImGui_End();
}

fn drawHierarchyNode(self: *Self, world: ecs.World, entity: ecs.Entity, level: usize, ctx: *GameApp) !void {
    const uuid = ctx.world.getUuid(entity);
    const name = world.getName(entity);
    var child_it = world.children(entity);
    defer child_it.deinit();
    var has_next = child_it.next();

    c.ImGui_PushID(&uuid.?.urnZ());
    defer c.ImGui_PopID();
    var node_flags = c.ImGuiTreeNodeFlags_OpenOnArrow | c.ImGuiTreeNodeFlags_SpanAvailWidth | c.ImGuiTreeNodeFlags_DefaultOpen;
    if (!has_next) {
        node_flags |= c.ImGuiTreeNodeFlags_Leaf;
    }
    if (Editor.instance().selection.contains(.entity, entity)) {
        node_flags |= c.ImGuiTreeNodeFlags_Selected;
    }

    const avail = noZero(c.ImGui_GetContentRegionAvail());

    const edge_size = (c.ImGui_GetFrameHeight() + c.ImGui_GetStyle().*.FramePadding.y) / 3;
    {
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
            if (c.ImGui_AcceptDragDropPayload("Entity", 0)) |payload| { // drop above entity
                const payload_obj: ?*ecs.Entity = @ptrCast(@alignCast(payload.*.Data.?));
                if (payload_obj) |pl| {
                    if (pl.* != entity) {
                        const parent = c.ecs_get_parent(ctx.world.inner, entity);
                        Editor.trySetParentKeepUniquePathName(ctx.world, pl.*, parent, ctx.allocator) catch |err| switch (err) {
                            error.CyclicRelation => _ = try Editor.messageBox(.{
                                .title = "Error!",
                                .message = "Invalid Cyclic Relationship!",
                                .kind = .err,
                                .buttons = &[1]c.SDL_MessageBoxButtonData{
                                    .{ .buttonID = 0, .text = "Ok" },
                                },
                            }),
                            error.Cancel => {},
                            else => return err,
                        };
                        try ctx.world.changeEntityOrder(pl.*, ctx.world.getHierarchyOrder(entity), ctx.allocator);
                    }
                }
            }
            c.ImGui_EndDragDropTarget();
        }
    }
    c.ImGui_SetCursorPosY(c.ImGui_GetCursorPosY() - edge_size);

    const open = c.ImGui_TreeNodeEx("##", node_flags);
    if (!try drawContextMenu(entity, ctx)) {
        if (open) {
            c.ImGui_TreePop();
        }
        return;
    }
    if (c.ImGui_IsItemClicked() and !c.ImGui_IsItemToggledOpen()) {
        Editor.instance().selection = .{ .entity = entity };
    }

    if (c.ImGui_BeginDragDropTarget()) {
        if (c.ImGui_AcceptDragDropPayload("Entity", 0)) |payload| { // drop on entity
            const payload_obj: ?*ecs.Entity = @ptrCast(@alignCast(payload.*.Data.?));
            if (payload_obj) |p| {
                Editor.trySetParentKeepUniquePathName(ctx.world, p.*, entity, ctx.allocator) catch |err| switch (err) {
                    error.CyclicRelation => _ = try Editor.messageBox(.{
                        .title = "Error!",
                        .message = "Invalid Cyclic Relationship!",
                        .kind = .err,
                        .buttons = &[1]c.SDL_MessageBoxButtonData{
                            .{ .buttonID = 0, .text = "Ok" },
                        },
                    }),
                    error.Cancel => {},
                    else => return err,
                };
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
        while (has_next) : (has_next = child_it.next()) {
            for (0..@intCast(child_it.inner.count)) |i| {
                try self.drawHierarchyNode(world, child_it.inner.entities[i], level + 1, ctx);
            }
        }
        c.ImGui_TreePop();
    }
}

fn drawContextMenu(entity: ecs.Entity, ctx: *GameApp) !bool {
    var cont = true;
    if (c.ImGui_BeginPopupContextItemEx("context-menu", c.ImGuiPopupFlags_MouseButtonRight)) {
        if (c.ImGui_BeginMenu("New")) {
            if (c.ImGui_MenuItem("Entity")) {
                _ = ctx.world.entity(.{ .name = "New Entity", .parent = entity });
            }
            c.ImGui_Separator();
            if (c.ImGui_MenuItem("Cube")) {
                const new_entity = ctx.world.entity(.{ .name = "Cube", .parent = entity });
                ctx.world.set(new_entity, ecs.components.Mesh, (try Assets.getOrLoadMesh(try AssetsDatabase.getResourceId("builtin://cube.obj"))).*);
                ctx.world.set(new_entity, ecs.components.Material, (try Assets.getOrLoadMaterial(try AssetsDatabase.getResourceId("builtin://materials/none.mat"))).*);
            }
            _ = c.ImGui_MenuItem("Sphere*");
            _ = c.ImGui_MenuItem("Plane*");
            c.ImGui_Separator();
            if (c.ImGui_MenuItem("Camera")) {
                const new_entity = ctx.world.entity(.{ .name = "Camera", .parent = entity });
                ctx.world.set(new_entity, ecs.components.Camera, ecs.components.Camera.makePerspectiveCamera(.{
                    .fovy_rad = std.math.degreesToRadians(75),
                    .near = 0.1,
                    .far = 200,
                }));
            }
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

fn noZero(i: c.ImVec2) c.ImVec2 {
    var r = i;
    if (r.x == 0) {
        r.x = 0.01;
    }
    if (r.y == 0) {
        r.y = 0.01;
    }
    return r;
}
