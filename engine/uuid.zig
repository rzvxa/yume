const std = @import("std");

const uuid_zig = @import("uuid");

pub const Urn = uuid_zig.urn.Urn;
const Self = @This();

raw: u128,

pub inline fn new() Self {
    return .{ .raw = uuid_zig.v4.new() };
}

pub inline fn urn(self: Self) Urn {
    return uuid_zig.urn.serialize(self.raw);
}

pub inline fn urnZ(self: Self) [37]u8 {
    var buf = std.mem.zeroes([37]u8);
    const u = uuid_zig.urn.serialize(self.raw);
    @memcpy(buf[0..36], &u);
    buf[36] = 0;
    return buf;
}
