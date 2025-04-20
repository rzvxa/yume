const c = @import("clibs");
const std = @import("std");

const ecs = @import("../ecs.zig");
const utils = @import("../utils.zig");

pub const Meta = extern struct {
    name: [*c]u8,

    pub fn init(name: [*:0]const u8) !@This() {
        const span = std.mem.span(name);
        const self = Meta{
            .name = @ptrCast(try ecs.malloc(@sizeOf(u8) * span.len + 1)),
        };
        @memcpy(self.name[0 .. span.len + 1], name[0 .. span.len + 1]);
        return self;
    }

    pub fn setName(self: *@This(), new_name: [*:0]const u8) !void {
        const span = std.mem.span(new_name);
        if (self.name == null) {
            self.* = try init(new_name);
            return;
        }
        self.name = @ptrCast(try ecs.realloc(self.name, span.len + 1));
        @memcpy(self.name[0 .. span.len + 1], new_name[0 .. span.len + 1]);
    }

    pub fn deinit(self: *@This()) void {
        ecs.free(self.name);
    }
};
