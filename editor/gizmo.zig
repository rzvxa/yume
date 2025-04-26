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
    is_over_any: bool = false,
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

    context.is_over_any = false;
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

pub inline fn isOver() bool {
    return c.ImGuizmo_IsOver_Nil();
}

pub inline fn isOverAny() bool {
    return context.is_over_any;
}

pub inline fn isUsingAny() bool {
    return c.ImGuizmo_IsUsingAny();
}

pub fn editTransform(matrix: *Mat4, tool: ManipulationTool) !bool {
    try drawSanityCheck(&context);

    c.ImGuizmo_SetRect(c.ImGui_GetWindowPos().x, c.ImGui_GetWindowPos().y, context.viewport.width, context.viewport.height);
    var view = context.view;
    var proj = context.projection;
    const result = c.ImGuizmo_Manipulate(&view.values, &proj.values, @intFromEnum(tool), c.IMGUIZMO_WORLD, &matrix.values, null, null, null, null);
    context.is_over_any = context.is_over_any or c.ImGuizmo_IsOver_Nil();
    return result;
}

// Converts a 3D point into NDC, without clamping the x/y values.
fn toNdcPoint(vec: Vec3) ?Vec2 {
    const ndc = context.view_projection.mulVec3(vec);

    if (ndc.z > 1 or ndc.z < -1) return null;
    return Vec2{ .x = ndc.x, .y = ndc.y };
}

// Liang–Barsky line clipping on a line in NDC coordinates.
fn clipLine(a: Vec2, b: Vec2) ?[2]Vec2 {
    var t0: f32 = 0.0;
    var t1: f32 = 1.0;
    const dx = b.x - a.x;
    const dy = b.y - a.y;

    // We'll define the clip boundaries: left=-1, right=1, bottom=-1, top=1.
    // Each call adjusts t0 and t1 based on one boundary.
    if (!clipBoundary(-dx, a.x + 1, &t0, &t1)) return null; // Left boundary
    if (!clipBoundary(dx, 1 - a.x, &t0, &t1)) return null; // Right boundary
    if (!clipBoundary(-dy, a.y + 1, &t0, &t1)) return null; // Bottom boundary
    if (!clipBoundary(dy, 1 - a.y, &t0, &t1)) return null; // Top boundary

    if (t0 > t1) return null; // No visible segment.

    const newA = Vec2{ .x = a.x + t0 * dx, .y = a.y + t0 * dy };
    const newB = Vec2{ .x = a.x + t1 * dx, .y = a.y + t1 * dy };
    return [2]Vec2{ newA, newB };
}

// Liang–Barsky
fn clipBoundary(p: f32, q: f32, t0: *f32, t1: *f32) bool {
    if (p == 0) {
        // Line is parallel to this clipping boundary
        if (q < 0) return false; // Outside
    } else {
        const r = q / p;
        if (p < 0) {
            if (r > t1.*) return false;
            if (r > t0.*) t0.* = r;
        } else {
            if (r < t0.*) return false;
            if (r < t1.*) t1.* = r;
        }
    }
    return true;
}

fn ndcToScreen(ndc: Vec2) c.ImVec2 {
    return c.ImVec2{
        .x = (ndc.x + 1) * 0.5 * context.viewport.width + context.viewport.x,
        .y = (ndc.y + 1) * 0.5 * context.viewport.height + context.viewport.y,
    };
}

pub fn drawBoundingBox(bounds: BoundingBox, transform: Mat4) DrawError!void {
    try drawSanityCheck(&context);

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

    var worldPoints: [8]Vec3 = undefined;
    for (localPoints, 0..) |pt, i| {
        worldPoints[i] = transform.mulVec3(pt);
    }

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

    for (edges) |edge| {
        const ndc_a_opt = toNdcPoint(edge[0]);
        const ndc_b_opt = toNdcPoint(edge[1]);
        if (ndc_a_opt == null or ndc_b_opt == null) continue;

        const ndc_a = ndc_a_opt.?;
        const ndc_b = ndc_b_opt.?;

        const clippedOpt = clipLine(ndc_a, ndc_b);
        if (clippedOpt == null) continue;
        const clippedLine = clippedOpt.?;

        const screen_a = ndcToScreen(clippedLine[0]);
        const screen_b = ndcToScreen(clippedLine[1]);

        c.ImDrawList_AddLine(context.drawlist, screen_a, screen_b, red());
    }
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
