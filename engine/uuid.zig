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
