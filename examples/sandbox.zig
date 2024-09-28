const std = @import("std");
const yume = @import("yume");
const GameApp = yume.GameApp;

pub fn main() !void {
    var app = try GameApp.create();
    defer app.destroy();

    try app.run();
    std.debug.print("Bye!", .{});
}
