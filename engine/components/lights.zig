const std = @import("std");

const Dynamic = @import("../serialization/dynamic.zig").Dynamic;

const ecs = @import("../ecs.zig");
const GameApp = @import("../GameApp.zig");
const math3d = @import("../math3d.zig");
const Vec3 = math3d.Vec3;
const Vec4 = math3d.Vec4;

pub const PointLight = extern struct {
    color: Vec3 = Vec3.scalar(1),
    intensity: f32 = 0.3,

    pub fn editorIcon() [*:0]const u8 {
        return "editor://icons/point-light.png";
    }

    pub fn editorBillboard() [*:0]const u8 {
        return "editor://icons/point-light.png";
    }

    pub fn default(ptr: *PointLight, _: ecs.Entity, _: *GameApp, _: ecs.ResourceResolver) callconv(.C) bool {
        ptr.* = .{};
        return true;
    }

    pub fn serialize(self: *const @This(), a: std.mem.Allocator) !Dynamic {
        const fields = try a.alloc(Dynamic.Field, 2);
        fields[0] = .{
            .key = try a.dupeZ(u8, "color"),
            .value = try self.color.serialize(a),
        };
        fields[1] = .{
            .key = try a.dupeZ(u8, "intensity"),
            .value = .{ .type = .number, .value = .{ .number = self.intensity } },
        };
        return .{ .type = .object, .value = .{ .object = .{ .items = fields.ptr, .len = fields.len } } };
    }

    pub fn deserialize(self: *@This(), value: *const Dynamic, a: std.mem.Allocator) !void {
        const obj = try value.expectObject();
        var color = Vec3.ZERO;
        try Vec3.deserialize(&color, &(try obj.expectField("color")).value, a);
        self.* = .{
            .color = color,
            .intensity = try (try obj.expectField("intensity")).value.expectNumber(),
        };
    }
};
