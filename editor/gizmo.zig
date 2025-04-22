const c = @import("clibs");

const std = @import("std");

const yume = @import("yume");

const Vec2 = yume.Vec2;
const Vec3 = yume.Vec3;
const Mat4 = yume.Mat4;
const Rect = yume.Rect;

const BoundingBox = @import("yume").ecs.components.mesh.BoundingBox;

pub const ManipulationTool = enum(c_uint) {
    move_x = c.IMGUIZMO_TRANSLATE_X,
    move_y = c.IMGUIZMO_TRANSLATE_Y,
    move_z = c.IMGUIZMO_TRANSLATE_Z,
    rotate_x = c.IMGUIZMO_ROTATE_X,
    rotate_y = c.IMGUIZMO_ROTATE_Y,
    rotate_z = c.IMGUIZMO_ROTATE_Z,
    rotate_screen = c.IMGUIZMO_ROTATE_SCREEN,
    scale_x = c.IMGUIZMO_SCALE_X,
    scale_y = c.IMGUIZMO_SCALE_Y,
    scale_z = c.IMGUIZMO_SCALE_Z,
    bounds = c.IMGUIZMO_BOUNDS,
    scale_xu = c.IMGUIZMO_SCALE_XU,
    scale_yu = c.IMGUIZMO_SCALE_YU,
    scale_zu = c.IMGUIZMO_SCALE_ZU,
    move = c.IMGUIZMO_TRANSLATE,
    rotate = c.IMGUIZMO_ROTATE,
    scale = c.IMGUIZMO_SCALE,
    scale_u = c.IMGUIZMO_SCALEU,
    transform = c.IMGUIZMO_UNIVERSAL,
};

const GizmoContext = struct {
    inframe: bool = false,
    drawlist: [*c]c.ImDrawList = undefined,
    view: *Mat4 = undefined,
    projection: Mat4 = Mat4.IDENTITY,
    view_projection: Mat4 = Mat4.IDENTITY,
    viewport: Rect = std.mem.zeroes(Rect),
};

var context: GizmoContext = .{};

pub fn newFrame(drawlist: [*c]c.ImDrawList, view: *Mat4, projection: Mat4, dist: f32, viewport: Rect) void {
    if (context.inframe) {
        @panic("can't start a new frame while in frame");
    }

    context.drawlist = drawlist;

    context.projection = projection;
    context.projection.unnamed[1][1] *= -1.0;

    context.view = view;
    context.view_projection = projection.mul(context.view.*);

    context.viewport = viewport;

    context.inframe = true;

    c.ImGuizmo_SetDrawlist(drawlist);

    const viewManipulateRight = c.ImGui_GetWindowPos().x + context.viewport.width;
    const viewManipulateTop = c.ImGui_GetWindowPos().y;
    c.ImGuizmo_ViewManipulate_Float(
        &context.view.values,
        dist,
        c.ImVec2{ .x = viewManipulateRight - 128, .y = viewManipulateTop },
        c.ImVec2{ .x = 128, .y = 128 },
        0x10101010,
    );
}

pub fn endFrame() void {
    context.inframe = false;
}

pub fn editTransform(matrix: *Mat4, tool: ManipulationTool) !bool {
    try drawSanityCheck(&context);

    // const window_width = c.ImGui_GetWindowWidth();
    // const window_height = c.ImGui_GetWindowHeight();
    c.ImGuizmo_SetRect(c.ImGui_GetWindowPos().x, c.ImGui_GetWindowPos().y, context.viewport.width, context.viewport.height);
    var view = context.view;
    var proj = context.projection;
    return c.ImGuizmo_Manipulate(&view.values, &proj.values, @intFromEnum(tool), c.IMGUIZMO_WORLD, &matrix.values, null, null, null, null);
}

pub fn drawBoundingBox(bounds: BoundingBox, transform: Mat4) DrawError!void {
    try drawSanityCheck(&context);

    // Define the eight corner points in local space.
    const localPoints = [8]Vec3{
        Vec3{ .x = bounds.mins.x, .y = bounds.mins.y, .z = bounds.mins.z },
        Vec3{ .x = bounds.maxs.x, .y = bounds.mins.y, .z = bounds.mins.z },
        Vec3{ .x = bounds.mins.x, .y = bounds.maxs.y, .z = bounds.mins.z },
        Vec3{ .x = bounds.maxs.x, .y = bounds.maxs.y, .z = bounds.mins.z },
        Vec3{ .x = bounds.mins.x, .y = bounds.mins.y, .z = bounds.maxs.z },
        Vec3{ .x = bounds.maxs.x, .y = bounds.mins.y, .z = bounds.maxs.z },
        Vec3{ .x = bounds.mins.x, .y = bounds.maxs.y, .z = bounds.maxs.z },
        Vec3{ .x = bounds.maxs.x, .y = bounds.maxs.y, .z = bounds.maxs.z },
    };

    // Transform the local points to world space.
    var worldPoints: [8]Vec3 = undefined;
    for (localPoints, 0..) |pt, i| {
        worldPoints[i] = transform.mulVec3(pt);
    }

    // Define edges using the world-space points.
    const edges = [_][2]Vec3{
        .{ worldPoints[0], worldPoints[1] },
        .{ worldPoints[0], worldPoints[2] },
        .{ worldPoints[0], worldPoints[4] },
        .{ worldPoints[1], worldPoints[3] },
        .{ worldPoints[1], worldPoints[5] },
        .{ worldPoints[2], worldPoints[3] },
        .{ worldPoints[2], worldPoints[6] },
        .{ worldPoints[3], worldPoints[7] },
        .{ worldPoints[4], worldPoints[5] },
        .{ worldPoints[4], worldPoints[6] },
        .{ worldPoints[5], worldPoints[7] },
        .{ worldPoints[6], worldPoints[7] },
    };

    // Convert the world points to screen-space and draw the edges.
    for (edges) |edge| {
        const a = toScreenPoint(edge[0]);
        const b = toScreenPoint(edge[1]);
        // Don't draw if either point is offscreen.
        if (a == null or b == null) {
            continue;
        }
        c.ImDrawList_AddLine(context.drawlist, a.?, b.?, red());
    }
}

fn toScreenPoint(vec: Vec3) ?c.ImVec2 {
    var view_proj_vec = context.view_projection.mulVec3(vec);

    if (view_proj_vec.z > 1 or view_proj_vec.z < -1) {
        return null;
    }

    if (view_proj_vec.x > 1) {
        view_proj_vec.x = 1;
    } else if (view_proj_vec.x < -1) {
        view_proj_vec.x = -1;
    }
    if (view_proj_vec.y > 1) {
        view_proj_vec.y = 1;
    } else if (view_proj_vec.y < -1) {
        view_proj_vec.y = -1;
    }

    var point = c.ImVec2{
        .x = (view_proj_vec.x + 1) * 0.5 * context.viewport.width,
        .y = (view_proj_vec.y + 1) * 0.5 * context.viewport.height,
    };

    // Apply the possible offsets
    point.x += context.viewport.x;
    point.y += context.viewport.y;

    return point;
}

fn drawSanityCheck(g: *const GizmoContext) DrawError!void {
    if (!g.inframe) {
        return error.NotInAFrame;
    }
}

pub const DrawError = error{NotInAFrame};

fn black() c.ImU32 {
    return c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0, .y = 0, .z = 0, .w = 1 });
}

fn red() c.ImU32 {
    return c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 });
}

fn green() c.ImU32 {
    return c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 });
}

fn blue() c.ImU32 {
    return c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0, .y = 0, .z = 1, .w = 1 });
}

fn darkenColor(color: u32, percentage: u8) u32 {
    const r: u8 = @intCast((color >> 16) & 0xFF);
    const g: u8 = @intCast((color >> 8) & 0xFF);
    const b: u8 = @intCast(color & 0xFF);

    const new_r = darken(r, percentage);
    const new_g = darken(g, percentage);
    const new_b = darken(b, percentage);

    return (color & 0xFF000000) | (new_r << 16) | (new_g << 8) | new_b;
}

fn darken(col: u8, p: u8) u32 {
    return @truncate(@as(u32, @intCast(@max(0, col))) - @as(u32, @intCast(col)) * p / 100);
}
