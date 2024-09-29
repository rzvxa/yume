/// Based on:
/// <https://zig.news/xq/cool-zig-patterns-type-identifier-3mfd>
/// Found it on <https://github.com/ryupold/zecsi/blob/main/src/ecs/archetype_storage.zig#L846>
/// Thanks to both of you guys!
///
///
typeid: usize,

const TypeId = @This();

pub fn new(comptime T: type) TypeId {
    _ = T;
    const H = struct {
        var byte: u8 = 0;
    };
    return .{ .typeid = @intFromPtr(&H.byte) };
}
