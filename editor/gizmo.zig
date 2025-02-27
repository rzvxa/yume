const c = @import("clibs");

const std = @import("std");

const yume = @import("yume");

const Vec2 = yume.Vec2;
const Vec3 = yume.Vec3;
const Mat4 = yume.Mat4;
const Rect = yume.Rect;

const BoundingBox = @import("yume").Mesh.BoundingBox;

const GizmoContext = struct {
    inframe: bool = false,
    drawlist: [*c]c.ImDrawList = undefined,
    view_projection: Mat4 = Mat4.IDENTITY,
    viewport: Rect = std.mem.zeroes(Rect),
};

var context: GizmoContext = .{};

pub fn newFrame(drawlist: [*c]c.ImDrawList, view_projection: Mat4, viewport: Rect) void {
    if (context.inframe) {
        @panic("can't start a new frame while in frame");
    }
    context.drawlist = drawlist;
    context.view_projection = view_projection;
    context.viewport = viewport;
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

    const red = c.ImGui_GetColorU32ImVec4(c.ImVec4{ .x = 1, .y = 0, .z = 0, .w = 1 });
    for (edges) |edge| {
        c.ImDrawList_AddLine(
            context.drawlist,
            toScreenPoint(edge[0]),
            toScreenPoint(edge[1]),
            red,
        );
    }
}

fn toScreenPoint(vec: Vec3) c.ImVec2 {
    const view_proj_vec = context.view_projection.mulVec3(vec);
    var point = c.ImVec2{
        .x = (view_proj_vec.x + 1) * 0.5 * context.viewport.width,
        .y = (view_proj_vec.y + 1) * 0.5 * context.viewport.height,
    };

    // apply the possible offsets
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
