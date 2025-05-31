const c = @import("clibs");

const std = @import("std");

const yume = @import("yume");

const Vec2 = yume.Vec2;
const Vec3 = yume.Vec3;
const Vec4 = yume.Vec4;
const Mat4 = yume.Mat4;
const Rect = yume.Rect;

const BoundingBox = @import("yume").meshes.BoundingBox;

pub const ManipulationMode = enum(c_uint) {
    local = c.IMGUIZMO_LOCAL,
    world = c.IMGUIZMO_WORLD,
};

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

    {
        const style = c.ImGui_GetStyle();
        const right = c.ImGui_GetWindowPos().x + context.viewport.width;
        const top = c.ImGui_GetWindowPos().y;
        c.ImGuizmo_ViewManipulate_Float(
            &context.view.values,
            dist,
            c.ImVec2{ .x = right - 128 + style.*.FramePadding.x, .y = top + style.*.FramePadding.y },
            c.ImVec2{ .x = 128, .y = 128 },
            0x10101010,
        );
    }
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

pub fn editTransform(local_to_world_matrix: *Mat4, tool: ManipulationTool, mode: ManipulationMode) !bool {
    try drawSanityCheck(&context);

    c.ImGuizmo_SetRect(c.ImGui_GetWindowPos().x, c.ImGui_GetWindowPos().y, context.viewport.width, context.viewport.height);
    var view = context.view;
    var proj = context.projection;
    const result = c.ImGuizmo_Manipulate(
        &view.values,
        &proj.values,
        @intFromEnum(tool),
        @intFromEnum(mode),
        &local_to_world_matrix.values,
        null,
        null,
        null,
        null,
    );
    context.is_over_any = context.is_over_any or c.ImGuizmo_IsOver_Nil();

    return result;
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
        drawEdge(edge[0], edge[1], red(), 1, 0);
    }
}

pub fn drawBoundingBoxCorners(bounds: BoundingBox, transform: Mat4) DrawError!void {
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

    const corner_factor = 4;

    const offsetX = (bounds.maxs.x - bounds.mins.x) / corner_factor;
    const offsetY = (bounds.maxs.y - bounds.mins.y) / corner_factor;
    const offsetZ = (bounds.maxs.z - bounds.mins.z) / corner_factor;

    // For each corner, determine three endpoint positions (one for each axis) in local space.
    // The offset direction is determined by whether the corner's coordinate equals the min or max.
    for (localPoints, 0..) |cornerLocal, i| {
        const cornerWorld = worldPoints[i];

        // X-axis line: if the local corner is at the min x, move positive; if at max, move negative.
        var endLocalX: Vec3 = cornerLocal;
        if (cornerLocal.x == bounds.mins.x) {
            endLocalX.x += offsetX;
        } else {
            endLocalX.x -= offsetX;
        }

        // Y-axis line: if the local corner is at the min y, move positive; if at max, move negative.
        var endLocalY: Vec3 = cornerLocal;
        if (cornerLocal.y == bounds.mins.y) {
            endLocalY.y += offsetY;
        } else {
            endLocalY.y -= offsetY;
        }

        // Z-axis line: if the local corner is at the min z, move positive; if at max, move negative.
        var endLocalZ: Vec3 = cornerLocal;
        if (cornerLocal.z == bounds.mins.z) {
            endLocalZ.z += offsetZ;
        } else {
            endLocalZ.z -= offsetZ;
        }

        // Transform the local endpoints to world space.
        const endWorldX = transform.mulVec3(endLocalX);
        const endWorldY = transform.mulVec3(endLocalY);
        const endWorldZ = transform.mulVec3(endLocalZ);

        const color = c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0, .y = 208.0 / 255.0, .z = 208.0 / 255.0, .w = 1 });
        // Draw three short segments from the corner to these endpoints.
        // Using drawEdge with segments == 1 draws a single segment without gradient.
        drawEdge(cornerWorld, endWorldX, color, 1, 0);
        drawEdge(cornerWorld, endWorldY, color, 1, 0);
        drawEdge(cornerWorld, endWorldZ, color, 1, 0);
    }
}

// Draws the camera frustum using the provided inverse view–projection matrix.
// The canonical eight corners in NDC (with near plane z = -1 and far plane z = 1)
// are unprojected to world space and then the near, far, and side edges are drawn.
pub fn drawFrustum(inv_view_proj: Mat4) DrawError!void {
    try drawSanityCheck(&context);

    // Define the eight canonical NDC corners.
    const ndc_corners: [8]Vec3 = [_]Vec3{
        Vec3{ .x = -1, .y = -1, .z = -1 }, // near plane
        Vec3{ .x = 1, .y = -1, .z = -1 },
        Vec3{ .x = -1, .y = 1, .z = -1 },
        Vec3{ .x = 1, .y = 1, .z = -1 },
        Vec3{ .x = -1, .y = -1, .z = 1 }, // far plane
        Vec3{ .x = 1, .y = -1, .z = 1 },
        Vec3{ .x = -1, .y = 1, .z = 1 },
        Vec3{ .x = 1, .y = 1, .z = 1 },
    };

    // Unproject NDC corners to world space using the provided inv_view_proj.
    var world_corners: [8]Vec3 = undefined;
    for (ndc_corners, 0..) |corner, idx| {
        world_corners[idx] = inv_view_proj.mulVec3(corner);
    }

    // Define the indices for the frustum edges.
    // Near-plane edges (indices 0..3):
    const near_edges: [4][2]usize = [_][2]usize{
        .{ 0, 1 },
        .{ 1, 3 },
        .{ 3, 2 },
        .{ 2, 0 },
    };

    // Far-plane edges (indices 4..7):
    const far_edges: [4][2]usize = [_][2]usize{
        .{ 4, 5 },
        .{ 5, 7 },
        .{ 7, 6 },
        .{ 6, 4 },
    };

    // Side edges (connect corresponding near and far corners):
    const side_edges: [4][2]usize = [_][2]usize{
        .{ 0, 4 },
        .{ 1, 5 },
        .{ 2, 6 },
        .{ 3, 7 },
    };

    // Draw near plane, far plane, and side edges.
    for (near_edges) |edge| {
        drawEdge(world_corners[edge[0]], world_corners[edge[1]], green(), 50, 50);
    }
    for (far_edges) |edge| {
        drawEdge(world_corners[edge[0]], world_corners[edge[1]], green(), 50, 50);
    }
    for (side_edges) |edge| {
        drawEdge(world_corners[edge[0]], world_corners[edge[1]], green(), 50, 50);
    }
}

pub fn drawBillboardIcon(str_id: [*c]const u8, world_pos: Vec3, icon: c.ImTextureID, icon_size: f32) bool {
    c.ImGui_PushID(str_id);
    defer c.ImGui_PopID();

    // Transform the world-space point into clip space using a homogeneous Vec4.
    const pos4 = context.view_projection.mulVec4(Vec4.make(
        world_pos.x,
        world_pos.y,
        world_pos.z,
        1.0,
    ));

    // Ensure we have a non-zero w for perspective division.
    if (pos4.w == 0.0) return false;
    const ndc_x: f32 = pos4.x / pos4.w;
    const ndc_y: f32 = pos4.y / pos4.w;
    const ndc_z: f32 = pos4.z / pos4.w;

    // If the point is outside the view depth, skip drawing.
    if (ndc_z < 0 or ndc_z > 1) return false;

    // Build a 2D NDC position.
    const ndc_pos = Vec2{ .x = ndc_x, .y = ndc_y };

    // Convert NDC coordinates to screen space.
    const screen_pos = ndcToScreen(ndc_pos);

    // Compute the icon rectangle, centered at screen_pos.
    const half_size: f32 = icon_size * 0.5;
    var p_min = c.ImVec2{
        .x = screen_pos.x - half_size,
        .y = screen_pos.y - half_size,
    };
    var p_max = c.ImVec2{
        .x = screen_pos.x + half_size,
        .y = screen_pos.y + half_size,
    };

    // Clamp the destination rectangle to the viewport.
    if (p_min.x < context.viewport.x) {
        p_min.x = context.viewport.x;
    }
    if (p_min.y < context.viewport.y) {
        p_min.y = context.viewport.y;
    }
    if (p_max.x > context.viewport.x + context.viewport.width) {
        p_max.x = context.viewport.x + context.viewport.width;
    }
    if (p_max.y > context.viewport.y + context.viewport.height) {
        p_max.y = context.viewport.y + context.viewport.height;
    }

    // If the resulting rectangle has non-positive area, it's off–screen.
    if (p_min.x >= p_max.x or p_min.y >= p_max.y) return false;

    // Create an invisible button over the icon's area.
    const button_size = c.ImVec2{
        .x = p_max.x - p_min.x,
        .y = p_max.y - p_min.y,
    };
    const cursor = c.ImGui_GetCursorScreenPos();
    c.ImGui_SetCursorScreenPos(p_min);
    const clicked = c.ImGui_InvisibleButton(str_id, button_size, 0);

    // Draw the image using ImGui's draw list.
    c.ImDrawList_AddImage(context.drawlist, icon, p_min, p_max);

    c.ImGui_SetCursorScreenPos(cursor);
    return clicked;
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

    const new_a = Vec2{ .x = a.x + t0 * dx, .y = a.y + t0 * dy };
    const new_b = Vec2{ .x = a.x + t1 * dx, .y = a.y + t1 * dy };
    return [2]Vec2{ new_a, new_b };
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

/// Clip a 3D line segment to the near and far planes in camera space.
/// 'a' and 'b' are world–space endpoints.
/// Returns the interpolated (clipped) endpoints in world space.
fn clipLine3D(a: Vec3, b: Vec3, near: f32, far: f32) ?[2]Vec3 {
    // Transform endpoints into camera space.
    const ca = context.view.mulVec3(a);
    const cb = context.view.mulVec3(b);

    var t0: f32 = 0.0;
    var t1: f32 = 1.0;
    const dz = cb.z - ca.z;

    // For a perspective camera looking down -Z:
    // near plane is at z = -near and far plane at z = -far.
    if (!clipBoundary(dz, (-near) - ca.z, &t0, &t1)) return null;
    if (!clipBoundary(-dz, ca.z - (-far), &t0, &t1)) return null;
    if (t0 > t1) return null;

    return [2]Vec3{
        a.lerp(b, t0),
        a.lerp(b, t1),
    };
}

/// Draws a line edge that fades toward the far end.
/// If segments == 1, the edge is drawn as a single segment with the original color.
/// Otherwise, the edge is subdivided into (segments+1) points and a gradient is applied.
pub fn drawEdge(world1: Vec3, world2: Vec3, color: c.ImU32, segments: usize, max_darken_percent: u8) void {
    // used for line clipping, perhaps it should use the editor's near/far? debug lines are cheap to draw
    const near_distance: f32 = 0.1;
    const far_distance: f32 = 10000.0;

    // First clip the 3D line segment.
    const clipped3D_opt = clipLine3D(world1, world2, near_distance, far_distance);
    if (clipped3D_opt == null) return;
    const clipped3D = clipped3D_opt.?;

    if (segments == 1) {
        // Single segment: project endpoints and draw one line.
        const ndc_a = context.view_projection.mulVec3(clipped3D[0]);
        const ndc_b = context.view_projection.mulVec3(clipped3D[1]);
        const a_ndc = Vec2{ .x = ndc_a.x, .y = ndc_a.y };
        const b_ndc = Vec2{ .x = ndc_b.x, .y = ndc_b.y };
        const screen_a = ndcToScreen(a_ndc);
        const screen_b = ndcToScreen(b_ndc);
        c.ImDrawList_AddLine(context.drawlist, screen_a, screen_b, color);
        return;
    }

    // We'll darken the color gradually from 0% at t = 0 (near end)
    // to max_darken_percent at t = 1 (far end).
    var prev_screen: c.ImVec2 = undefined;
    var first = true;

    // Loop from 0 to segments (inclusive) to get (segments + 1) points.
    for (0..(segments + 1)) |i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments));
        const world_pos: Vec3 = clipped3D[0].lerp(clipped3D[1], t);
        const ndc_vec: Vec3 = context.view_projection.mulVec3(world_pos);
        const ndc_pos: Vec2 = Vec2{ .x = ndc_vec.x, .y = ndc_vec.y };
        const screen_pos: c.ImVec2 = ndcToScreen(ndc_pos);

        // Compute the darkening percentage: 0 at near (t=0) to max_darken_percent at far (t=1).
        const darken_prec: u8 = @as(u8, @intFromFloat(t * @as(f32, @floatFromInt(max_darken_percent))));
        const segcol: c.ImU32 = darkenColor(color, darken_prec);

        if (!first) {
            c.ImDrawList_AddLine(context.drawlist, prev_screen, screen_pos, segcol);
        } else {
            first = false;
        }
        prev_screen = screen_pos;
    }
}

pub fn drawCircle(
    origin: Vec3,
    axis_x: Vec3,
    axis_y: Vec3,
    radius: f32,
    color: c.ImU32,
    segments: usize,
) void {
    var prev: Vec3 = origin.add(axis_x.mulf(radius));
    for (0..segments) |i| {
        const angle: f32 = 2.0 * std.math.pi * (@as(f32, @floatFromInt(i + 1))) / @as(f32, @floatFromInt(segments));
        const curr: Vec3 = origin.add(axis_x.mulf(radius * std.math.cos(angle))
            .add(axis_y.mulf(radius * std.math.sin(angle))));
        drawEdge(prev, curr, color, 1, 0);
        prev = curr;
    }
}

pub fn drawSphere(
    origin: Vec3,
    radius: f32,
    color: c.ImU32,
    segments: usize,
) void {
    // Circle in the XY plane.
    drawCircle(origin, Vec3.make(1, 0, 0), Vec3.make(0, 1, 0), radius, color, segments);
    // Circle in the XZ plane.
    drawCircle(origin, Vec3.make(1, 0, 0), Vec3.make(0, 0, 1), radius, color, segments);
    // Circle in the YZ plane.
    drawCircle(origin, Vec3.make(0, 1, 0), Vec3.make(0, 0, 1), radius, color, segments);
}

fn drawSanityCheck(g: *const GizmoContext) DrawError!void {
    if (!g.inframe) {
        return error.NotInAFrame;
    }
}

pub const DrawError = error{NotInAFrame};

pub fn black() c.ImU32 {
    return c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0, .y = 0, .z = 0, .w = 1 });
}

pub fn red() c.ImU32 {
    return c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 });
}

pub fn green() c.ImU32 {
    return c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 0, .y = 1, .z = 0, .w = 1 });
}

pub fn blue() c.ImU32 {
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
