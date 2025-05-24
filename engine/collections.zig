const std = @import("std");

const utils = @import("utils.zig");

pub fn StringSentinelArrayHashMap(comptime sentinel: u8, comptime V: type) type {
    return std.ArrayHashMap([:sentinel]const u8, V, ArrayHashMapStringSentinelContext(sentinel), true);
}

pub fn StringSentinelHashMap(comptime sentinel: u8, comptime V: type) type {
    return std.HashMap([:sentinel]const u8, V, HashMapStringSentinelContext(sentinel), std.hash_map.default_max_load_percentage);
}

pub fn ArrayHashMapStringSentinelContext(comptime sentinel: u8) type {
    return struct {
        pub fn hash(_: @This(), s: [:sentinel]const u8) u32 {
            return @as(u32, @truncate(std.hash.Wyhash.hash(0, s)));
        }
        pub fn eql(_: @This(), a: [:sentinel]const u8, b: [:sentinel]const u8, _: usize) bool {
            return std.mem.eql(u8, a, b);
        }
    };
}

pub const ArrayHashMapStringAdaptedContext = struct {
    pub fn hash(s: []const u8) u32 {
        return @as(u32, @truncate(std.hash.Wyhash.hash(0, s)));
    }
    pub fn eql(a: []const u8, b: []const u8, _: usize) bool {
        return std.mem.eql(u8, a, b);
    }
};

pub fn ArrayHashMapStringSentinelSortContext(comptime sentinel: u8) type {
    return struct {
        keys: [][:sentinel]const u8,
        pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
            return std.ascii.lessThanIgnoreCase(ctx.keys[a_index], ctx.keys[b_index]);
        }
    };
}

pub fn HashMapStringSentinelContext(comptime sentinel: u8) type {
    return struct {
        pub fn hash(_: @This(), s: [:sentinel]const u8) u64 {
            return std.hash.Wyhash.hash(0, s);
        }
        pub fn eql(_: @This(), a: [:sentinel]const u8, b: [:sentinel]const u8) bool {
            return std.mem.eql(u8, a, b);
        }
    };
}

pub const HashMapStringAdaptedContext = struct {
    pub fn hash(s: []const u8) u64 {
        return std.hash.Wyhash.hash(0, s);
    }
    pub fn eql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};
