const c = @import("clibs");
const std = @import("std");

const GameApp = @import("yume").GameApp;
const Object = @import("yume").scene_graph.Object;
const ecs = @import("yume").ecs;
const components = @import("yume").components;

const Editor = @import("../Editor.zig");

const Self = @This();

pub fn draw(_: *Self, ctx: *GameApp) !void {
    if (c.ImGui_Begin("Properties", null, 0)) {
        switch (Editor.instance().selection) {
            .entity => |e| try drawProperties(e, ctx),
            else => {},
        }
    }
    c.ImGui_End();
}

fn drawProperties(entity: ecs.Entity, ctx: *GameApp) !void {
    // FIXME
    var buf: [256]u8 = undefined;
    const gui_id = try std.fmt.bufPrint(&buf, "{}", .{entity});
    c.ImGui_PushID(gui_id.ptr);
    defer c.ImGui_PopID();

    Editor.instance().editors.editEntityMeta(entity, ctx);
    c.ImGui_Spacing();

    c.ImGui_Separator();

    c.ImGui_Spacing();
    Editor.instance().editors.editEntityTransform(entity, ctx);
    c.ImGui_Spacing();

    c.ImGui_Separator();

    c.ImGui_Spacing();

    const typ = c.ecs_get_type(ctx.world.inner, entity);
    const editor = Editor.instance();

    for (0..@intCast(typ[0].count)) |i| {
        const id: c.ecs_id_t = typ[0].array[i];
        if (id & c.ECS_PAIR > 0) {
            continue;
        }
        const comp = id & c.ECS_COMPONENT_MASK;

        const type_id = c.ecs_get_typeid(ctx.world.inner, comp);
        const ed = editor.editors.componentEditorOf(type_id) orelse continue;
        editor.editors.editComponent(ed, entity, comp, ctx);

        c.ImGui_Separator();

        for (0..2) |_| c.ImGui_Spacing();
    }

    if (c.ImGui_CollapsingHeader("Debug Info", c.ImGuiTreeNodeFlags_None)) {
        for (0..@intCast(typ[0].count)) |i| {
            const id: c.ecs_id_t = typ[0].array[i];
            const id_str = c.ecs_id_str(ctx.world.inner, id);
            c.ImGui_Text(id_str);
        }
    }

    c.ImGui_Spacing();

    const style = c.ImGui_GetStyle();
    const label = "Add Component";
    const alignment = 0.5;

    const size = @max(c.ImGui_CalcTextSize(label).x + style.*.FramePadding.x * 2, 200);
    const avail = c.ImGui_GetContentRegionAvail().x;
    const popup_id = "###add_component_popup";

    const off = (avail - size) * alignment;
    if (off > 0) {
        c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + off);
    }

    if (c.ImGui_ButtonEx(label, c.ImVec2{ .x = size, .y = 0 })) {
        c.ImGui_OpenPopup(popup_id, 0);
    }

    if (c.ImGui_BeginPopup(popup_id, 0)) {
        c.ImGui_Text("Name:");
        c.ImGui_SameLine();
        var query: [1024]u8 = undefined;
        query[0] = 0;
        _ = c.ImGui_InputText("###component_name", &query, 1024, 0);
        {
            var iter = ctx.components.iterator();
            while (iter.next()) |it| {
                if (it.value_ptr.default) |default| {
                    if (c.ImGui_Button(it.key_ptr.ptr)) {
                        c.ImGui_CloseCurrentPopup();
                        switch (Editor.instance().selection) {
                            .entity => |e| {
                                ctx.world.setId(e, it.value_ptr.id, it.value_ptr.size, undefined);
                                const ref = c.ecs_get_mut_id(ctx.world.inner, e, it.value_ptr.id);
                                std.debug.assert(default(ref.?, e, ctx));
                            },
                            else => {},
                        }
                    }
                }
            }
        }
        if (c.ImGui_Button("Add###add_component")) {
            c.ImGui_CloseCurrentPopup();
        }
        c.ImGui_SameLine();
        if (c.ImGui_Button("Create###create_component")) {
            c.ImGui_CloseCurrentPopup();
        }
        c.ImGui_EndPopup();
    }
}
