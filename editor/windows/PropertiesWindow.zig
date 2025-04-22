const c = @import("clibs");
const std = @import("std");

const Uuid = @import("yume").Uuid;
const GameApp = @import("yume").GameApp;
const ecs = @import("yume").ecs;
const utils = @import("yume").utils;

const Editor = @import("../Editor.zig");
const AssetsDatabase = @import("../AssetsDatabase.zig");

const Self = @This();

pub fn init(_: *GameApp) Self {
    return .{};
}

pub fn deinit(_: *Self) void {}

pub fn draw(self: *Self, ctx: *GameApp) !void {
    if (c.ImGui_Begin("Properties", null, c.ImGuiWindowFlags_NoCollapse)) {
        switch (Editor.instance().selection) {
            .entity => |e| try self.drawProperties(e, ctx),
            else => {},
        }
    }
    c.ImGui_End();
}

fn drawProperties(_: *Self, entity: ecs.Entity, ctx: *GameApp) !void {
    var buf: [256]u8 = undefined;
    const gui_id = try std.fmt.bufPrint(&buf, "{}", .{entity});
    c.ImGui_PushID(gui_id.ptr);
    defer c.ImGui_PopID();

    Editor.instance().editors.editEntityMeta(entity, ctx);
    c.ImGui_Separator();

    for (0..2) |_| c.ImGui_Spacing();

    if (ctx.world.has(entity, ecs.components.Transform)) {
        Editor.instance().editors.editEntityTransform(entity, ctx);
        c.ImGui_Spacing();
        c.ImGui_Separator();
        for (0..2) |_| c.ImGui_Spacing();
    }

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

    c.ImGui_Separator();

    c.ImGui_Spacing();

    const style = c.ImGui_GetStyle();
    const label = "Add Component";
    const alignment = 0.5;

    const popup_id = "###add_component_popup";
    {
        const size = @max(c.ImGui_CalcTextSize(label).x + style.*.FramePadding.x * 2, 200);
        const avail = c.ImGui_GetContentRegionAvail().x;

        const off = (avail - size) * alignment;
        if (off > 0) {
            c.ImGui_SetCursorPosX(c.ImGui_GetCursorPosX() + off);
        }

        if (c.ImGui_ButtonEx(label, c.ImVec2{ .x = size, .y = 0 })) {
            c.ImGui_OpenPopup(popup_id, 0);
        }
    }

    if (c.ImGui_BeginPopup(popup_id, 0)) {
        c.ImGui_Text("Name:");
        c.ImGui_SameLine();
        var query: [1024]u8 = undefined;
        query[0] = 0;
        _ = c.ImGui_InputText("###component_name", &query, 1024, 0);
        c.ImGui_Separator();
        {
            const avail = c.ImGui_GetContentRegionAvail().x;
            const pad = style.*.FramePadding;
            const Scored = struct {
                lev: usize,
                key: []const u8,
                name: [:0]const u8,
            };
            var sfa = std.heap.stackFallback(2048, ctx.allocator);
            const a = sfa.get();
            var filtered = std.ArrayList(Scored).init(a);
            defer filtered.deinit();

            {
                var iter = ctx.components.iterator();
                while (iter.next()) |it| {
                    if (it.value_ptr.default) |_| {
                        const name = ctx.world.getName(it.value_ptr.id);
                        const lev = utils.levenshtein(
                            name,
                            std.mem.span(@as([*c]const u8, query[0..])),
                            ctx.allocator,
                        );

                        try filtered.append(.{
                            .lev = lev,
                            .key = it.key_ptr.*,
                            .name = name,
                        });
                    }
                }
            }

            std.mem.sort(Scored, filtered.items, {}, struct {
                fn cmp(_: void, lhs: Scored, rhs: Scored) bool {
                    return std.sort.asc(usize)({}, lhs.lev, rhs.lev);
                }
            }.cmp);

            for (filtered.items) |it| {
                const def = ctx.components.get(it.key).?;
                c.ImGui_PushID(it.key.ptr);
                const clicked = blk: {
                    const icon_size = 16;
                    const label_size = c.ImGui_CalcTextSize(it.key.ptr);
                    const prepos = c.ImGui_GetCursorPos();
                    const btnsz = c.ImVec2{ .x = avail, .y = label_size.y + pad.y * 2 };
                    const clicked = c.ImGui_ButtonEx("##select-component-button", btnsz);
                    const resetpos = c.ImGui_GetCursorPos();

                    const label_pad_y = (btnsz.y - label_size.y) / 2;

                    const icon = if (def.icon) |icon_path|
                        try Editor.getImGuiTexture(std.mem.span(icon_path), &ctx.engine)
                    else
                        Editor.file_icon_ds;

                    const icon_pad_y = (btnsz.y - icon_size) / 2;

                    const icon_pos = c.ImVec2{
                        .x = prepos.x + 2 * pad.x,
                        .y = prepos.y + icon_pad_y,
                    };
                    c.ImGui_SetCursorPos(icon_pos);

                    c.ImGui_Image(icon, c.ImVec2{ .x = icon_size, .y = icon_size });
                    c.ImGui_SetCursorPosX(icon_pos.x + icon_size + (2 * pad.x));
                    c.ImGui_SetCursorPosY(prepos.y + label_pad_y - (pad.y / 2));

                    c.ImGui_Text(it.name);

                    const has_arrow = false;
                    if (has_arrow) {
                        const arrow_size = c.ImGui_CalcTextSize(">");
                        const arrow_pad_y = (btnsz.y - arrow_size.y) / 2;
                        c.ImGui_SameLine();
                        c.ImGui_SetCursorPosY(prepos.y + arrow_pad_y);
                        c.ImGui_SetCursorPosX(avail - 10);
                        c.ImGui_Text(">");
                    }
                    c.ImGui_SetCursorPos(resetpos);

                    break :blk clicked;
                };
                if (clicked) {
                    c.ImGui_CloseCurrentPopup();
                    switch (Editor.instance().selection) {
                        .entity => |e| {
                            ctx.world.setId(e, def.id, def.size, undefined);
                            const ref = c.ecs_get_mut_id(ctx.world.inner, e, def.id);
                            std.debug.assert(def.default.?(ref.?, e, ctx, extern struct {
                                fn f(path: [*:0]const u8) callconv(.C) ecs.ResourceResolverResult {
                                    const uuid = AssetsDatabase.getResourceId(std.mem.span(path)) catch return .{
                                        .found = false,
                                        .uuid = .{ .raw = 0 },
                                    };
                                    return .{ .found = true, .uuid = uuid };
                                }
                            }.f));
                        },
                        else => {},
                    }
                }
                c.ImGui_PopID();
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
