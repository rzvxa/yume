const std = @import("std");

pub fn assert(ok: bool, comptime format: []const u8, args: anytype) void {
    if (!ok) {
        comptime if (std.builtin.OptimizeMode == .Debug) {
            assertionMessage(format, args);
        };
        unreachable;
    }
}

pub inline fn debugAssert(ok: bool, comptime format: []const u8, args: anytype) void {
    comptime if (std.builtin.OptimizeMode == .Debug) {
        if (!ok) {
            assertionMessage(format, args);
            unreachable;
        }
    };
}

inline fn assertionMessage(comptime format: []const u8, args: anytype) void {
    std.debug.print("Assertion failed: ", .{});
    std.debug.print(format, args);
    std.debug.print("\n", .{});
}
