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
    engine_c_libs.use_clang = true;
    engine_c_libs.addIncludeDir("vendor/ufbx/");
    engine_c_libs.addIncludeDir("vendor/sdl3/include");
    engine_c_libs.addIncludeDir("vendor/vma/");
    engine_c_libs.addIncludeDir("vendor/stb/");

    const ufbx_lib = b.addStaticLibrary(.{
        .name = "ufbx",
        .target = target,
        .optimize = optimize,
    });
    ufbx_lib.addIncludePath(b.path("vendor/ufbx/"));
    ufbx_lib.linkLibC();
    ufbx_lib.addCSourceFiles(.{
        .files = &.{
            "vendor/ufbx/ufbx.c",
        },
    });

    const vk_lib_name = if (target.result.os.tag == .windows) "vulkan-1" else "vulkan";

    const uuid_dep = b.dependency("uuid_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const uuid_mod = uuid_dep.module("uuid");
    yume.addImport("uuid", uuid_mod);

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

    yume.linkLibrary(ufbx_lib);

    const engine_c_mod = engine_c_libs.createModule();
    yume.addImport("clibs", engine_c_mod);

    compile_all_shaders(b);

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
    imgui_lib.defineCMacro("IMGUI_USE_LEGACY_CRC32_ADLER", null);
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
}

fn compile_all_shaders(b: *std.Build) void {
    const shaders_dir =
        b.build_root.handle.openDir("shaders", .{ .iterate = true }) catch @panic("Failed to open shaders directory");

    var file_it = shaders_dir.iterate();
    while (file_it.next() catch @panic("Failed to iterate shader directory")) |entry| {
        if (entry.kind == .file) {
            const ext = std.fs.path.extension(entry.name);
            if (std.mem.eql(u8, ext, ".glsl")) {
                const basename = std.fs.path.basename(entry.name);
                const name = basename[0 .. basename.len - ext.len];

                std.debug.print("Found shader file to compile: {s}. Compiling with name: {s}\n", .{ entry.name, name });
                add_shader(b, name);
            }
        }
    }
}

fn add_shader(b: *std.Build, name: []const u8) void {
    const source = std.fmt.allocPrint(b.allocator, "shaders/{s}.glsl", .{name}) catch @panic("OOM");
    const outpath = std.fmt.allocPrint(b.allocator, ".shader-cache/{s}.spv", .{name}) catch @panic("OOM");

    const shader_compilation = b.addSystemCommand(&.{"glslangValidator"});
    shader_compilation.addArg("-V");
    shader_compilation.addArg("-o");
    const output = shader_compilation.addOutputFileArg(outpath);
    shader_compilation.addFileArg(b.path(source));

    b.getInstallStep().dependOn(&b.addInstallFileWithDir(output, .{ .custom = "../" }, outpath).step);
}
