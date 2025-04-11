const c = @import("clibs");

const GameApp = @import("yume").GameApp;
const Object = @import("yume").scene_graph.Object;
const ecs = @import("yume").ecs;

const Editor = @import("../Editor.zig");

const Self = @This();

pub fn draw(_: *Self, ctx: *GameApp) void {
    if (c.ImGui_Begin("Properties", null, 0)) {
        switch (Editor.instance().selection) {
            .entity => |e| drawProperties(e, ctx),
            else => {},
        }
    }
    c.ImGui_End();
}

fn drawProperties(_: ecs.Entity, _: *GameApp) void {
    // FIXME
    // c.ImGui_PushID(&obj.uuid.urn());
    // defer c.ImGui_PopID();
    // Editor.instance().editors.editObjectMeta(obj, Editor.object_icon_ds);
    // c.ImGui_Spacing();
    // c.ImGui_Separator();
    // c.ImGui_Spacing();
    // Editor.instance().editors.editObjectTransform(obj);
    // c.ImGui_Spacing();
    // c.ImGui_Separator();
    // c.ImGui_Spacing();
    // for (obj.components.items) |*comp| {
    //     Editor.instance().editors.editComponent(obj, comp);
    //     c.ImGui_Separator();
    //     c.ImGui_Spacing();
    //     c.ImGui_Spacing();
    // }
    //
    // c.ImGui_Spacing();
    //
    // const style = c.ImGui_GetStyle();
    // const label = "Add Component";
    // const alignment = 0.5;
    //
    // const size = @max(c.ImGui_CalcTextSize(label).x + style.*.FramePadding.x * 2, 200);
    // const avail = c.ImGui_GetContentRegionAvail().x;
    // const popup_id = "###add_component_popup";
    //
    // const off = (avail - size) * alignment;
    // if (off > 0) {
    //     c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + off);
    // }
    //
    // if (c.ImGui_ButtonEx(label, c.ImVec2{ .x = size, .y = 0 })) {
    //     c.ImGui_OpenPopup(popup_id, 0);
    // }
    //
    // if (c.ImGui_BeginPopup(popup_id, 0)) {
    //     c.ImGui_Text("Name:");
    //     c.ImGui_SameLine();
    //     var query: [1024]u8 = undefined;
    //     query[0] = 0;
    //     _ = c.ImGui_InputText("###component_name", &query, 1024, 0);
    //     {
    //         var iter = ctx.components.iterator();
    //         while (iter.next()) |it| {
    //             if (c.ImGui_Button(it.key_ptr.ptr)) {
    //                 c.ImGui_CloseCurrentPopup();
    //                 Editor.instance().selection.?.addComponentDynamic(it.value_ptr);
    //             }
    //         }
    //     }
    //     if (c.ImGui_Button("Add###add_component")) {
    //         c.ImGui_CloseCurrentPopup();
    //     }
    //     c.ImGui_SameLine();
    //     if (c.ImGui_Button("Create###create_component")) {
    //         c.ImGui_CloseCurrentPopup();
    //     }
    //     c.ImGui_EndPopup();
    // }
}
