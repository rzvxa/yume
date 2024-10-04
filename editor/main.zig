const std = @import("std");
const yume = @import("yume");
const GameApp = yume.GameApp;

pub fn main() !void {
    var app = try GameApp.init("Yume Editor");
    defer app.deinit();

    try app.run();
    std.debug.print("Bye!", .{});
}
