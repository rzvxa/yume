const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const yume = b.addModule("yume", .{
        .root_source_file = b.path("engine/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const engine_c_libs = b.addTranslateC(.{
        .root_source_file = b.path("engine/clibs.c"),
        .target = target,
        .optimize = optimize,
    });
    const vk_lib_name = if (target.result.os.tag == .windows) "vulkan-1" else "vulkan";

    yume.linkSystemLibrary("SDL3", .{});
    yume.linkSystemLibrary(vk_lib_name, .{});
    yume.addLibraryPath(.{ .cwd_relative = "vendor/sdl3/lib" });
    const env_map = try std.process.getEnvMap(b.allocator);
    if (env_map.get("VK_SDK_PATH")) |path| {
        yume.addLibraryPath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "{s}/lib", .{path}) catch @panic("OOM") });
        yume.addIncludePath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "{s}/include", .{path}) catch @panic("OOM") });
        engine_c_libs.addIncludeDir(std.fmt.allocPrint(b.allocator, "{s}/include", .{path}) catch @panic("OOM"));
    }
    yume.addCSourceFile(.{ .file = b.path("engine/vk_mem_alloc.cpp"), .flags = &.{""} });
    yume.addCSourceFile(.{ .file = b.path("engine/stb_image.c"), .flags = &.{""} });

    yume.addIncludePath(.{ .cwd_relative = "vendor/vma/" });
    yume.addIncludePath(.{ .cwd_relative = "vendor/stb/" });

    engine_c_libs.addIncludeDir("vendor/sdl3/include");
    engine_c_libs.addIncludeDir("vendor/vma/");
    engine_c_libs.addIncludeDir("vendor/stb/");
    const engine_c_mod = engine_c_libs.createModule();
    yume.addImport("clibs", engine_c_mod);

    compile_all_shaders(b, yume);

    const editor = b.addExecutable(.{
        .name = "yume editor",
        .root_source_file = b.path("editor/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    engine_c_libs.addIncludeDir("vendor/imgui/");
    editor.root_module.addImport("clibs", engine_c_mod);

    if (env_map.get("VK_SDK_PATH")) |path| {
        editor.addIncludePath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "{s}/include", .{path}) catch @panic("OOM") });
    }
    editor.addIncludePath(.{ .cwd_relative = "vendor/sdl3/include" });
    editor.addIncludePath(b.path("vendor/vma/"));
    editor.addIncludePath(b.path("vendor/stb/"));
    editor.addIncludePath(b.path("vendor/imgui/"));

    editor.linkLibCpp();
    editor.root_module.addImport("yume", yume);
    compile_all_shaders(b, &editor.root_module);

    b.installArtifact(editor);
    if (target.result.os.tag == .windows) {
        b.installBinFile("vendor/sdl3/lib/SDL3.dll", "SDL3.dll");
    } else {
        b.installBinFile("vendor/sdl3/lib/libSDL3.so", "libSDL3.so.0");
        editor.root_module.addRPathSpecial("$ORIGIN");
    }

    // Imgui (with cimgui and vulkan + sdl3 backends)
    const imgui_lib = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = target,
        .optimize = optimize,
    });
    if (env_map.get("VK_SDK_PATH")) |path| {
        imgui_lib.addIncludePath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "{s}/include", .{path}) catch @panic("OOM") });
    }
    imgui_lib.addIncludePath(b.path("vendor/imgui/"));
    imgui_lib.addIncludePath(b.path("vendor/sdl3/include/"));
    imgui_lib.linkLibCpp();
    imgui_lib.addCSourceFiles(.{
        .files = &.{
            "vendor/imgui/imgui.cpp",
            "vendor/imgui/imgui_demo.cpp",
            "vendor/imgui/imgui_draw.cpp",
            "vendor/imgui/imgui_tables.cpp",
            "vendor/imgui/imgui_widgets.cpp",
            "vendor/imgui/imgui_impl_sdl3.cpp",
            "vendor/imgui/imgui_impl_vulkan.cpp",
            "vendor/imgui/cimgui.cpp",
            "vendor/imgui/cimgui_internal.cpp",
            "vendor/imgui/cimgui_impl_sdl3.cpp",
            "vendor/imgui/cimgui_impl_vulkan.cpp",
        },
    });

    editor.linkLibrary(imgui_lib);

    const run_cmd = b.addRunArtifact(editor);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // const unit_tests = b.addTest(.{
    //     .root_source_file = b.path("editor/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_unit_tests = b.addRunArtifact(unit_tests);

    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_unit_tests.step);
}

fn compile_all_shaders(b: *std.Build, mod: *std.Build.Module) void {
    // This is a fix for a change between zig 0.11 and 0.12

    const shaders_dir = if (@hasDecl(@TypeOf(b.build_root.handle), "openIterableDir"))
        b.build_root.handle.openIterableDir("shaders", .{}) catch @panic("Failed to open shaders directory")
    else
        b.build_root.handle.openDir("shaders", .{ .iterate = true }) catch @panic("Failed to open shaders directory");

    var file_it = shaders_dir.iterate();
    while (file_it.next() catch @panic("Failed to iterate shader directory")) |entry| {
        if (entry.kind == .file) {
            const ext = std.fs.path.extension(entry.name);
            if (std.mem.eql(u8, ext, ".glsl")) {
                const basename = std.fs.path.basename(entry.name);
                const name = basename[0 .. basename.len - ext.len];

                std.debug.print("Found shader file to compile: {s}. Compiling with name: {s}\n", .{ entry.name, name });
                add_shader(b, mod, name);
            }
        }
    }
}

fn add_shader(b: *std.Build, mod: *std.Build.Module, name: []const u8) void {
    const source = std.fmt.allocPrint(b.allocator, "shaders/{s}.glsl", .{name}) catch @panic("OOM");
    const outpath = std.fmt.allocPrint(b.allocator, "shaders/{s}.spv", .{name}) catch @panic("OOM");

    const shader_compilation = b.addSystemCommand(&.{"glslangValidator"});
    shader_compilation.addArg("-V");
    shader_compilation.addArg("-o");
    const output = shader_compilation.addOutputFileArg(outpath);
    shader_compilation.addFileArg(b.path(source));

    mod.addAnonymousImport(name, .{ .root_source_file = output });
}
