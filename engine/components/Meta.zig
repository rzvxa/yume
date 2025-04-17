const c = @import("clibs");
const std = @import("std");

const utils = @import("../utils.zig");

pub const Meta = extern struct {
    allocator: *anyopaque, // FIXME: unsound
    title: [*:0]const u8,

    pub fn deinit(self: *@This()) void {
        const span = std.mem.span(self.title);
        self.a().free(span);
    }

    fn a(self: *@This()) *std.mem.Allocator {
        return @ptrCast(@alignCast(self.allocator));
    }
};
