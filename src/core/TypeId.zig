/// Based on:
/// <https://zig.news/xq/cool-zig-patterns-type-identifier-3mfd>
/// Found it on <https://github.com/ryupold/zecsi/blob/main/src/ecs/archetype_storage.zig#L846>
/// Thanks to both of you guys!
///
///
raw: usize,

const std = @import("std");
const TypeId = @This();

pub fn new(comptime T: type) TypeId {
    _ = T;
    const H = struct {
        var byte: u8 = 0;
    };
    return .{ .raw = @intFromPtr(&H.byte) };
}

pub fn sort(_: void, a: TypeId, b: TypeId) bool {
    return a.raw < b.raw;
}

pub fn eql(self: TypeId, other: TypeId) bool {
    return self.raw == other.raw;
}
