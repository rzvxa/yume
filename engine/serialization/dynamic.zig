const std = @import("std");

pub const Dynamic = extern struct {
    pub const Type = enum(u8) {
        null, // null | undefined | unit or anything else representing nothingness
        bool,
        number,
        string,
        array,
        object,
    };
    pub const Value = extern union {
        null: void,
        bool: bool,
        number: f32,
        string: [*:0]u8,
        array: [*]Dynamic,
        object: [*]Field,
    };
    pub const Field = extern struct {
        key: [*:0]u8,
        value: Dynamic,
    };

    type: Type,
    value: Value,
    count: usize,

    pub fn expect(self: *const Dynamic, comptime ty: Type) !blk: {
        for (@typeInfo(Value).Union.fields) |field| {
            if (std.mem.eql(u8, field.name, @tagName(ty))) {
                break :blk field.type;
            }
        }
        @compileError("invalid type " ++ @tagName(ty));
    } {
        if (self.type == ty) {
            return @field(self.value, @tagName(ty));
        }
        return error.UnexpectedType;
    }

    pub fn jsonParse(allocator: std.mem.Allocator, jrs: *std.json.Scanner, o: anytype) !Dynamic {
        switch (try jrs.next()) {
            .null => {
                return .{ .type = .null, .value = .{ .null = {} }, .count = 1 };
            },
            .true => {
                return .{ .type = .bool, .value = .{ .bool = true }, .count = 1 };
            },
            .false => {
                return .{ .type = .bool, .value = .{ .bool = false }, .count = 1 };
            },
            .number, .allocated_number => |slice| {
                const number = std.fmt.parseFloat(f32, slice) catch return error.SyntaxError;
                return .{ .type = .number, .value = .{ .number = number }, .count = 1 };
            },
            .string, .allocated_string => |slice| {
                return .{ .type = .string, .value = .{ .string = try allocator.dupeZ(u8, slice) }, .count = slice.len };
            },
            .array_begin => {
                var array = std.ArrayList(Dynamic).init(allocator);
                while (true) {
                    if (try jrs.peekNextTokenType() == .array_end) {
                        _ = try jrs.next();
                        break;
                    }
                    const element = try Dynamic.jsonParse(allocator, jrs, o);
                    try array.append(element);
                }
                const count = array.items.len;
                return .{ .type = .array, .value = .{ .array = (try array.toOwnedSlice()).ptr }, .count = count };
            },
            .object_begin => {
                var fields = std.ArrayList(Field).init(allocator);
                while (true) {
                    if (try jrs.peekNextTokenType() == .object_end) {
                        _ = try jrs.next();
                        break;
                    }
                    const key = blk: {
                        const key = try Dynamic.jsonParse(allocator, jrs, o);
                        break :blk switch (key.type) {
                            inline .string => key.value.string,
                            else => return error.UnexpectedToken,
                        };
                    };
                    const value = try Dynamic.jsonParse(allocator, jrs, o);
                    try fields.append(.{ .key = key, .value = value });
                }
                const count = fields.items.len;
                return .{ .type = .object, .value = .{ .object = (try fields.toOwnedSlice()).ptr }, .count = count };
            },
            else => return error.UnexpectedToken,
        }
    }
};
