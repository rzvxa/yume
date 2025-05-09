const std = @import("std");

const utils = @import("utils.zig");

pub fn StringSentinelArrayHashMap(comptime sentinel: u8, comptime V: type) type {
    return std.ArrayHashMap([:sentinel]const u8, V, StringSentinelContext(sentinel), true);
}

pub fn StringSentinelContext(comptime sentinel: u8) type {
    return struct {
        pub fn hash(_: @This(), s: [:sentinel]const u8) u32 {
            return @as(u32, @truncate(std.hash.Wyhash.hash(0, s)));
        }
        pub fn eql(_: @This(), a: [:sentinel]const u8, b: [:sentinel]const u8, _: usize) bool {
            return std.mem.eql(u8, a, b);
        }
    };
}
