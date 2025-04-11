const uuid = @import("../uuid.zig");

pub const Uuid = extern struct { value: uuid.Uuid };
