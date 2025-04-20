const c = @import("clibs");

const std = @import("std");

const yume = @import("yume");
const GameApp = yume.GameApp;

const Editor = @import("Editor.zig");
const AssetsDatabase = @import("AssetsDatabase.zig");

const log_harness = @import("logs_harness.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("Leaked memory");
    };
    const allocator = gpa.allocator();

    var cwd_buff: [1024]u8 = undefined;
    const cwd = std.process.getCwd(cwd_buff[0..]) catch @panic("cwd_buff too small");
    std.log.info("Running from: {s}", .{cwd});

    try AssetsDatabase.init(allocator);
    defer AssetsDatabase.deinit();

    var app = GameApp.init(allocator, AssetsDatabase.readAssetAlloc, "Yume Editor");
    defer app.deinit();

    app.run(Editor);
}

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = log_harness.logFn,
};
