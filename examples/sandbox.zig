const std = @import("std");
const yume = @import("yume");
const GameApp = yume.GameApp;

pub fn main() !void {
    var app = try GameApp.new();
    try app.run();
    std.debug.print("Ok", .{});
}
