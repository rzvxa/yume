const c = @import("clibs");

const std = @import("std");

const yume = @import("yume");

const Vec2 = yume.Vec2;
const Vec3 = yume.Vec3;
const Mat4 = yume.Mat4;
const Rect = yume.Rect;

const BoundingBox = @import("yume").components.mesh.BoundingBox;

const GizmoContext = struct {
    inframe: bool = false,
    color: c.ImU32 = undefined,
    drawlist: [*c]c.ImDrawList = undefined,
    view: Mat4 = Mat4.IDENTITY,
    view_projection: Mat4 = Mat4.IDENTITY,
    viewport: Rect = std.mem.zeroes(Rect),
};

var context: GizmoContext = .{};

pub fn newFrame(drawlist: [*c]c.ImDrawList, view: Mat4, view_projection: Mat4, viewport: Rect) void {
    if (context.inframe) {
        @panic("can't start a new frame while in frame");
    }
    context.drawlist = drawlist;
    context.view = view;
    context.view_projection = view_projection;
    context.viewport = viewport;
    context.color = black();
    context.inframe = true;
}

pub fn endFrame() void {
    context.inframe = false;
}

pub fn drawBoundingBox(bounds: BoundingBox) DrawError!void {
    try drawSanityCheck(&context);
    const points = [8]Vec3{
        Vec3{ .x = bounds.mins.x, .y = bounds.mins.y, .z = bounds.mins.z },
        Vec3{ .x = bounds.maxs.x, .y = bounds.mins.y, .z = bounds.mins.z },
        Vec3{ .x = bounds.mins.x, .y = bounds.maxs.y, .z = bounds.mins.z },
        Vec3{ .x = bounds.maxs.x, .y = bounds.maxs.y, .z = bounds.mins.z },
        Vec3{ .x = bounds.mins.x, .y = bounds.mins.y, .z = bounds.maxs.z },
        Vec3{ .x = bounds.maxs.x, .y = bounds.mins.y, .z = bounds.maxs.z },
        Vec3{ .x = bounds.mins.x, .y = bounds.maxs.y, .z = bounds.maxs.z },
        Vec3{ .x = bounds.maxs.x, .y = bounds.maxs.y, .z = bounds.maxs.z },
    };
    const edges = [_][2]Vec3{
        .{ points[0], points[1] },
        .{ points[0], points[2] },
        .{ points[0], points[4] },
        .{ points[1], points[3] },
        .{ points[1], points[5] },
        .{ points[2], points[3] },
        .{ points[2], points[6] },
        .{ points[3], points[7] },
        .{ points[4], points[5] },
        .{ points[4], points[6] },
        .{ points[5], points[7] },
        .{ points[6], points[7] },
    };

    for (edges) |edge| {
        const a = toScreenPoint(edge[0]);
        const b = toScreenPoint(edge[1]);
        // don't draw offscreen lines
        if (a == null or b == null) {
            continue;
        }
        c.ImDrawList_AddLine(context.drawlist, a.?, b.?, red());
    }
}

fn pixelSize(n: f32) f32 {
    const a = c.ImVec2{ .x = 0, .y = 0 };
    const b = c.ImVec2{ .x = n, .y = 0 };
    const aworld = toWorldPosition(a);
    const bworld = toWorldPosition(b);
    const diff = bworld.sub(aworld);
    return diff.len();
}

pub fn drawArrow(from: Vec3, to: Vec3, thickness: f32, head_size: f32, outline_thickness: f32, outline_color: u32) DrawError!void {
    const color = context.color;
    const n = pixelSize(thickness);
    const head = head_size / n;

    const imvec0 = c.ImVec2{ .x = 0, .y = 0 };

    // Calculate the direction vector
    const direction = to.sub(from).normalized();
    const screen_to = toScreenPoint(to.sub(direction.mulf(head_size))) orelse imvec0;

    // Draw the main arrow line with outline
    c.ImDrawList_AddLineEx(
        context.drawlist,
        toScreenPoint(from) orelse imvec0,
        screen_to,
        outline_color,
        thickness + outline_thickness,
    );
    c.ImDrawList_AddLineEx(
        context.drawlist,
        toScreenPoint(from) orelse imvec0,
        screen_to,
        color,
        thickness,
    );

    // Create a basis for the perpendicular vector
    const upVector = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    var perpendicular = direction.cross(upVector);
    if (perpendicular.squaredLen() < 1e-6) {
        perpendicular = direction.cross(Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 });
    }
    perpendicular = perpendicular.normalized().mulf(head * 0.5);

    // Ensure the arrowhead is visible by making it a pyramid
    const right = perpendicular;
    const up = direction.cross(right).normalized().mulf(head * 0.5);

    const base1 = to.sub(direction.mulf(head_size)).add(right).add(up);
    const base2 = to.sub(direction.mulf(head_size)).add(right).sub(up);
    const base3 = to.sub(direction.mulf(head_size)).sub(right).sub(up);
    const base4 = to.sub(direction.mulf(head_size)).sub(right).add(up);
    const arrowTip = to;

    // Draw the 4 triangles to form the pyramid arrowhead with outline
    const drawTriangleWithOutline = struct {
        fn f(p1: Vec3, p2: Vec3, p3: Vec3, col: u32, out_col: u32) void {
            _ = out_col;
            const iv0 = c.ImVec2{ .x = 0, .y = 0 };
            c.ImDrawList_AddTriangleFilled(
                context.drawlist,
                toScreenPoint(p1) orelse iv0,
                toScreenPoint(p2) orelse iv0,
                toScreenPoint(p3) orelse iv0,
                col,
            );
        }
    }.f;

    drawTriangleWithOutline(base1, base2, arrowTip, color, outline_color);
    drawTriangleWithOutline(base2, base3, arrowTip, darkenColor(color, 10), outline_color);
    drawTriangleWithOutline(base3, base4, arrowTip, color, outline_color);
    drawTriangleWithOutline(base4, base1, arrowTip, darkenColor(color, 10), outline_color);
}

pub fn manipulate(pos: *Vec3, rot: *Vec3, scale: *Vec3) DrawError!void {
    const x_end = pos.add(Vec3.make(0.5, 0, 0));
    const y_end = pos.add(Vec3.make(0, 0.5, 0));
    const z_end = pos.add(Vec3.make(0, 0, 0.5));

    const thickness = 5;
    // const outline_thickness = 1;

    const col = context.color;

    context.color = red();
    try drawArrow(pos.*, x_end, thickness, 0.2, 1, black());
    context.color = green();
    try drawArrow(pos.*, y_end, thickness, 0.2, 1, black());
    context.color = blue();
    try drawArrow(pos.*, z_end, thickness, 0.2, 1, black());
    context.color = col;

    // c.ImDrawList_AddLineEx(context.drawlist, toScreenPoint(pos), toScreenPoint(x_end), black(), thickness + outline_thickness);
    // c.ImDrawList_AddLineEx(context.drawlist, toScreenPoint(pos), toScreenPoint(y_end), black(), thickness + outline_thickness);
    // c.ImDrawList_AddLineEx(context.drawlist, toScreenPoint(pos), toScreenPoint(z_end), black(), thickness + outline_thickness);
    // c.ImDrawList_AddTriangleFilled(
    //     context.drawlist,
    //     toScreenPoint(x_end.add(Vec3.make(0, 0.085, 0))),
    //     toScreenPoint(x_end.sub(Vec3.make(0, 0.085, 0))),
    //     toScreenPoint(x_end.add(Vec3.make(0.205, 0, 0))),
    //     black(),
    // );
    // c.ImDrawList_AddTriangleFilled(
    //     context.drawlist,
    //     toScreenPoint(x_end.add(Vec3.make(0, 0.08, 0))),
    //     toScreenPoint(x_end.sub(Vec3.make(0, 0.08, 0))),
    //     toScreenPoint(x_end.add(Vec3.make(0.2, 0, 0))),
    //     red(),
    // );
    // c.ImDrawList_AddLineEx(context.drawlist, toScreenPoint(pos), toScreenPoint(x_end), red(), thickness);
    // c.ImDrawList_AddLineEx(context.drawlist, toScreenPoint(pos), toScreenPoint(y_end), green(), thickness);
    // c.ImDrawList_AddLineEx(context.drawlist, toScreenPoint(pos), toScreenPoint(z_end), blue(), thickness);
    _ = rot;
    _ = scale;
}

fn toWorldPosition(screen_point: c.ImVec2) Vec3 {
    var ndc_x = (screen_point.x - context.viewport.x) / context.viewport.width;
    var ndc_y = (screen_point.y - context.viewport.y) / context.viewport.height;

    // Convert screen coordinates to NDC
    ndc_x = ndc_x * 2 - 1;
    ndc_y = ndc_y * 2 - 1;

    const ndc = Vec3.make(ndc_x, ndc_y, 1);

    // Apply the inverse of the view-projection matrix
    const inverse_view_projection = context.view_projection.inverse() catch Mat4.IDENTITY;
    const world_position = inverse_view_projection.mulVec3(ndc);

    return world_position;
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
