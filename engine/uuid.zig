const std = @import("std");
const log = std.log.scoped(.uuid);

const uuid_zig = @import("uuid");

pub const Urn = uuid_zig.urn.Urn;
pub const Uuid = extern struct {
    const Self = @This();

    raw: u128 align(8),

    pub inline fn new() Self {
        return .{ .raw = uuid_zig.v4.new() };
    }

    pub inline fn fromUrn(u: Urn) !Self {
        return fromUrnSlice(&u);
    }

    pub inline fn fromUrnSlice(s: []const u8) !Self {
        return Self{ .raw = try uuid_zig.urn.deserialize(s) };
    }

    pub inline fn urn(self: Self) Urn {
        return uuid_zig.urn.serialize(self.raw);
    }

    pub inline fn urnZ(self: Self) [36:0]u8 {
        var buf = std.mem.zeroes([36:0]u8);
        const u = uuid_zig.urn.serialize(self.raw);
        @memcpy(&buf, &u);
        buf[36] = 0;
        return buf;
    }

    pub inline fn eql(lhs: Self, rhs: Self) bool {
        return lhs.raw == rhs.raw;
    }

    pub fn jsonStringify(self: Self, jws: anytype) !void {
        return jws.write(self.urn());
    }

    pub fn jsonParse(a: std.mem.Allocator, jrs: anytype, _: anytype) !Self {
        const tk = try jrs.nextAlloc(a, .alloc_if_needed);

        const s = switch (tk) {
            inline .string, .allocated_string => |slice| slice,
            else => {
                log.err("{}\n", .{tk});
                return error.UnexpectedToken;
            },
        };

        return fromUrnSlice(s) catch error.UnexpectedToken;
    }
};
