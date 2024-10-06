const std = @import("std");
const yume = @import("yume");
const GameApp = yume.GameApp;

const Editor = struct {
    pub fn update(dt: f32) void {
        _ = dt;
    }
};

pub fn main() !void {
    var app = try GameApp.init("Yume Editor");
    defer app.deinit();

    try app.run(Editor);
    std.debug.print("Bye!", .{});
}
