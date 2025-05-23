const c = @import("clibs");

const std = @import("std");

const ecs = @import("yume").ecs;
const assets = @import("yume").assets;
const Assets = assets.Assets;
const GameApp = @import("yume").GameApp;
const Vec3 = @import("yume").Vec3;
const Mat4 = @import("yume").Mat4;
const Quat = @import("yume").Quat;

const Project = @import("../Project.zig");
const ProjectExplorerWindow = @import("../windows/ProjectExplorerWindow.zig");
const ComponentEditor = @import("editors.zig").ComponentEditor;
const imutils = @import("../imutils.zig");

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(a: std.mem.Allocator) *anyopaque {
    const ptr = a.create(@This()) catch @panic("OOM");
    ptr.* = @This(){ .allocator = a };
    return ptr;
}

pub fn deinit(ptr: *anyopaque) void {
    const me = @as(*@This(), @ptrCast(@alignCast(ptr)));
    me.allocator.destroy(me);
}

pub fn edit(_: *anyopaque, entity: ecs.Entity, _: ecs.Entity, ctx: *GameApp) void {
    var mesh = ctx.world.getMut(entity, ecs.components.Mesh).?;
    const result = imutils.assetHandleInput("Mesh", mesh.handle.toAssetHandle()) catch |err| blk: {
        std.log.err("Failed to display asset handle editor on the Mesh component, {}", .{err});
        break :blk null;
    };
    if (result) |new_handle| {
        new_handle_op: {
            const new_mesh = Assets.get(new_handle.unbox(.mesh)) catch break :new_handle_op;
            Assets.release(mesh.handle) catch {
                Assets.release(new_mesh) catch {};
                break :new_handle_op;
            };
            mesh.* = new_mesh.*;
        }
    }
}

pub fn asComponentEditor() ComponentEditor {
    return .{
        .init = @This().init,
        .deinit = @This().deinit,
        .edit = @This().edit,
    };
}
