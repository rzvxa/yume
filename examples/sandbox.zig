const std = @import("std");
const yume = @import("yume");
const GameApp = yume.GameApp;

pub fn main() !void {
    var app = try GameApp.init("Sandbox");
    defer app.deinit();

    try app.run(struct {});
    std.debug.print("Bye!", .{});
}
