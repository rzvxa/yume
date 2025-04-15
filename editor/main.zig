const c = @import("clibs");

const std = @import("std");

const GameApp = @import("yume").GameApp;

const Editor = @import("Editor.zig");
const Project = @import("Project.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        @panic("Leaked memory");
    };

    var cwd_buff: [1024]u8 = undefined;
    const cwd = std.process.getCwd(cwd_buff[0..]) catch @panic("cwd_buff too small");
    std.log.info("Running from: {s}", .{cwd});

    var app = GameApp.init(gpa.allocator(), Project.readAssetAlloc, "Yume Editor");
    defer app.deinit();

    app.run(Editor);
}
