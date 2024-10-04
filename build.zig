const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const vk_dep = b.dependency("vulkan_zig", .{
        .registry = @as([]const u8, b.pathFromRoot("vendor/vk.xml")),
    });
    const zig_ecs_dep = b.dependency("zig_ecs", .{
        .target = target,
        .optimize = optimize,
    });
    const glfw_dep = b.dependency("mach_glfw", .{
        .target = target,
        .optimize = optimize,
    });

    const vk_bindings = vk_dep.module("vulkan-zig");
    const zig_ecs_module = zig_ecs_dep.module("zig-ecs");
    const glfw_module = glfw_dep.module("mach-glfw");

    const yume = b.addModule("yume", .{
        .root_source_file = b.path("engine/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    yume.addImport("vulkan", vk_bindings);
    yume.addImport("zig-ecs", zig_ecs_module);
    yume.addImport("glfw", glfw_module);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    // b.installArtifact(lib);

    const editor = b.addExecutable(.{
        .name = "editor",
        .root_source_file = b.path("editor/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    editor.root_module.addImport("yume", yume);

    b.installArtifact(editor);

    const sandbox = b.addExecutable(.{
        .name = "sandbox",
        .root_source_file = b.path("examples/sandbox.zig"),
        .target = target,
        .optimize = optimize,
    });
    sandbox.root_module.addImport("yume", yume);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(sandbox);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const editor_cmd = b.addRunArtifact(editor);
    const sandbox_cmd = b.addRunArtifact(sandbox);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    editor_cmd.step.dependOn(b.getInstallStep());
    sandbox_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        for (args) |arg| {
            if (std.mem.eql(u8, arg, "--debug")) {
                editor_cmd.setEnvironmentVariable("VK_INSTANCE_LAYERS", "VK_LAYER_LUNARG_monitor:VK_LAYER_KHRONOS_validation");
            }
            editor_cmd.addArg(arg);
        }
    }

    if (b.args) |args| {
        sandbox_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const editor_step = b.step("editor", "run editor");
    editor_step.dependOn(&editor_cmd.step);

    const sandbox_step = b.step("sandbox", "run sandbox example");
    sandbox_step.dependOn(&sandbox_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("engine/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
