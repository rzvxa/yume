const std = @import("std");
const yume = @import("yume");
const GameApp = yume.GameApp;

pub fn main() !void {
    var app = try GameApp(struct {}).init("Sandbox");
    defer app.deinit();

    try app.run();
    std.debug.print("Bye!", .{});
}
