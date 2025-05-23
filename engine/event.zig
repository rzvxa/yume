const std = @import("std");
const Type = std.builtin.Type;

pub fn Event(comptime params: anytype) type {
    comptime var params_with_self: [@typeInfo(@TypeOf(params)).Struct.fields.len + 1]Type.Fn.Param = undefined;
    params_with_self[0] = .{
        .is_generic = false,
        .is_noalias = false,
        .type = *anyopaque,
    };

    inline for (params, 1..) |param, i| {
        params_with_self[i] = .{
            .is_generic = false,
            .is_noalias = false,
            .type = param,
        };
    }
    const CallbackOpequeFn = *const @Type(.{
        .Fn = .{
            .calling_convention = .Unspecified,
            .is_generic = false,
            .is_var_args = false,
            .params = &params_with_self,
            .return_type = void,
        },
    });
    return struct {
        pub const Callback = struct {
            self: *anyopaque,
            func: CallbackOpequeFn,

            pub fn call(cb: Callback, args: anytype) void {
                @call(.auto, cb.func, .{cb.self} ++ args);
            }

            pub fn eql(lhs: *const Callback, rhs: *const Callback) bool {
                return lhs.self == rhs.self and lhs.func == rhs.func;
            }
        };

        pub fn callback(comptime T: type, self: *T, comptime method: method_type: {
            var Ty = @typeInfo(@typeInfo(CallbackOpequeFn).Pointer.child);
            const type_params = [_]Type.Fn.Param{.{ .is_generic = false, .is_noalias = false, .type = *T }} ++ Ty.Fn.params[1..];
            Ty.Fn.params = type_params;
            break :method_type *const @Type(Ty);
        }) Callback {
            return .{
                .self = self,
                .func = @ptrCast(method),
            };
        }

        pub const List = struct {
            pub const CallKind = enum { always, once };

            allocator: std.mem.Allocator,
            always: std.ArrayListUnmanaged(Callback) = .{},
            once: std.ArrayListUnmanaged(Callback) = .{},

            pub fn init(allocator: std.mem.Allocator) List {
                return .{ .allocator = allocator };
            }

            pub fn deinit(self: *List) void {
                self.always.deinit(self.allocator);
                self.once.deinit(self.allocator);
            }

            pub fn fire(self: *List, args: anytype) void {
                for (self.always.items) |cb| {
                    cb.call(args);
                }

                for (self.once.items) |cb| {
                    cb.call(args);
                }
                self.once.clearRetainingCapacity();
            }

            pub fn append(list: *List, comptime kind: CallKind, cb: Callback) !void {
                return list.of(kind).append(list.allocator, cb);
            }

            pub fn appendUnique(list: *List, comptime kind: CallKind, cb: Callback) !void {
                for (list.of(kind).items) |it| {
                    if (it.eql(&cb)) {
                        return;
                    }
                }
                return list.of(kind).append(cb);
            }

            pub fn appendSlice(list: *List, comptime kind: CallKind, cbs: []const Callback) !void {
                return list.of(kind).appendSlice(list.allocator, cbs);
            }

            pub fn copyFrom(dst: *List, src: *const List) !void {
                try dst.appendSlice(.always, src.always.items);
                try dst.appendSlice(.once, src.once.items);
            }

            pub fn remove(list: *List, comptime kind: CallKind, cb: Callback) !void {
                for (list.of(kind).items, 0..) |it, i| {
                    if (it.eql(&cb)) {
                        _ = list.of(kind).orderedRemove(i);
                        return;
                    }
                }
                return error.CallbackNotFound;
            }

            fn of(list: *List, comptime kind: CallKind) *std.ArrayListUnmanaged(Callback) {
                return switch (comptime kind) {
                    .always => &list.always,
                    .once => &list.once,
                };
            }
        };
    };
}
