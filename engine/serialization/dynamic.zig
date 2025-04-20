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
        array: Elements,
        object: Fields,
    };
    pub const Elements = extern struct {
        items: [*]Dynamic,
        len: usize,

        pub inline fn elements(self: *const @This()) []const Dynamic {
            return self.items[0..self.len];
        }

        pub fn jsonStringify(self: Elements, jws: anytype) !void {
            try jws.write(self.elements());
        }
    };
    pub const Fields = extern struct {
        items: [*]Field,
        len: usize,

        pub inline fn fields(self: *const @This()) []const Field {
            return self.items[0..self.len];
        }

        pub fn field(self: *const @This(), name: [*:0]const u8) ?*const Field {
            for (self.fields()) |*f| {
                if (std.mem.eql(u8, std.mem.span(f.key), std.mem.span(name))) {
                    return f;
                }
            }
            return null;
        }

        pub fn expectField(self: *const @This(), name: [*:0]const u8) !*const Field {
            if (self.field(name)) |f| {
                return f;
            } else {
                return error.UndefinedField;
            }
        }

        pub fn jsonStringify(self: Fields, jws: anytype) !void {
            try jws.beginObject();
            for (self.fields()) |f| {
                try jws.objectField(std.mem.span(f.key));
                try jws.write(f.value);
            }
            try jws.endObject();
        }
    };
    pub const Field = extern struct {
        key: [*:0]u8,
        value: Dynamic,
    };

    type: Type,
    value: Value,

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

    pub inline fn expectNull(self: *const Dynamic) !void {
        return self.expect(.null);
    }

    pub inline fn expectBool(self: *const Dynamic) !bool {
        return self.expect(.bool);
    }

    pub inline fn expectNumber(self: *const Dynamic) !f32 {
        return self.expect(.number);
    }

    pub inline fn expectString(self: *const Dynamic) ![*:0]u8 {
        return self.expect(.string);
    }

    pub inline fn expectArray(self: *const Dynamic) !Elements {
        return self.expect(.array);
    }

    pub inline fn expectObject(self: *const Dynamic) !Fields {
        return self.expect(.object);
    }

    pub fn jsonParse(allocator: std.mem.Allocator, jrs: *std.json.Scanner, o: anytype) !Dynamic {
        switch (try jrs.next()) {
            .null => {
                return .{ .type = .null, .value = .{ .null = {} } };
            },
            .true => {
                return .{ .type = .bool, .value = .{ .bool = true } };
            },
            .false => {
                return .{ .type = .bool, .value = .{ .bool = false } };
            },
            .number, .allocated_number => |slice| {
                const number = std.fmt.parseFloat(f32, slice) catch return error.SyntaxError;
                return .{ .type = .number, .value = .{ .number = number } };
            },
            .string, .allocated_string => |slice| {
                return .{ .type = .string, .value = .{ .string = try allocator.dupeZ(u8, slice) } };
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
                return .{
                    .type = .array,
                    .value = .{ .array = .{ .items = (try array.toOwnedSlice()).ptr, .len = count } },
                };
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
                const len = fields.items.len;
                return .{
                    .type = .object,
                    .value = .{ .object = .{ .items = (try fields.toOwnedSlice()).ptr, .len = len } },
                };
            },
            else => return error.UnexpectedToken,
        }
    }

    pub fn jsonStringify(self: Dynamic, jws: anytype) !void {
        try switch (self.type) {
            .null => jws.write(null),
            .bool => jws.write(self.value.bool),
            .number => jws.write(self.value.number),
            .string => jws.write(self.value.string),
            .array => jws.write(self.value.array),
            .object => jws.write(self.value.object),
        };
    }
};
