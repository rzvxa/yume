const std = @import("std");

var init = std.once(struct {
    fn f() void {
        heap = std.heap.HeapAllocator.init();
        arena = std.heap.ArenaAllocator.init(heap.allocator());
        allocator = arena.allocator();
        logs = std.ArrayList(Log).init(allocator);
    }
}.f);

var heap: std.heap.HeapAllocator = undefined;
var arena: std.heap.ArenaAllocator = undefined;
var allocator: std.mem.Allocator = undefined;
var mutex = std.Thread.Mutex{};
var logs: std.ArrayList(Log) = undefined;

pub const Log = struct {
    level: std.log.Level,
    scope: [:0]const u8,
    message: [:0]const u8,
};

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    init.call();
    recordLog(.{
        .level = level,
        .scope = @tagName(scope),
        .message = std.fmt.allocPrintZ(allocator, format, args) catch return,
    });
    std.log.defaultLog(level, scope, format, args);
}

// returns number of drained items
pub fn drainInto(buf: *std.ArrayList(Log)) !usize {
    init.call();
    mutex.lock();
    defer mutex.unlock();

    const n = logs.items.len;
    try buf.appendSlice(logs.items);
    logs.clearRetainingCapacity();

    return n;
}

pub fn free(slice: []Log) void {
    for (slice) |log| {
        allocator.free(log.message);
    }
}

fn recordLog(log: Log) void {
    mutex.lock();
    defer mutex.unlock();
    logs.append(log) catch return;
}
