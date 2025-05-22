const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    assertTargetSupported(target);
    const sdl3_build = build_sdl3(b, target);

    const cfg = std.Build.Step.Options.create(b);
    cfg.addOption(std.SemanticVersion, "version", std.SemanticVersion{ .major = 0, .minor = 0, .patch = 1 });

    const yume = b.addModule("yume", .{
        .root_source_file = b.path("engine/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    yume.addOptions("cfg", cfg);

    const engine_c_libs = b.addTranslateC(.{
        .root_source_file = b.path("engine/c/clibs.c"),
        .target = target,
        .optimize = optimize,
    });
    engine_c_libs.use_clang = true;
    engine_c_libs.addIncludeDir("vendor/ufbx/");
    engine_c_libs.addIncludeDir("vendor/sdl3/include");
    engine_c_libs.addIncludeDir("vendor/vma/");
    engine_c_libs.addIncludeDir("vendor/stb/");
    engine_c_libs.addIncludeDir("vendor/flecs/");

    const ufbx_lib = b.addStaticLibrary(.{
        .name = "ufbx",
        .target = target,
        .optimize = optimize,
    });
    ufbx_lib.addIncludePath(b.path("vendor/ufbx/"));
    ufbx_lib.linkLibC();
    ufbx_lib.root_module.addCMacro("UFBX_CONFIG_HEADER", "\"ufbx_config.h\"");
    ufbx_lib.addCSourceFiles(.{
        .files = &.{
            "vendor/ufbx/ufbx.c",
        },
    });

    const env_map = try std.process.getEnvMap(b.allocator);
    const vk_lib_name = if (target.result.os.tag == .windows) "vulkan-1" else "vulkan";
    const vk_sdk_path = env_map.get("VULKAN_SDK") orelse env_map.get("VK_SDK_PATH");

    const uuid_dep = b.dependency("uuid_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const uuid_mod = uuid_dep.module("uuid");
    yume.addImport("uuid", uuid_mod);

    yume.addCMacro("VK_ENABLE_BETA_EXTENSIONS", "1");
    yume.linkSystemLibrary("SDL3", .{ .needed = true });
    yume.linkSystemLibrary(vk_lib_name, .{ .needed = true });
    yume.addLibraryPath(sdl3_build.lib_path);

    if (vk_sdk_path) |path| {
        yume.addLibraryPath(.{ .cwd_relative = try std.fmt.allocPrint(b.allocator, "{s}/lib", .{path}) });
        yume.addIncludePath(.{ .cwd_relative = try std.fmt.allocPrint(b.allocator, "{s}/include", .{path}) });
        engine_c_libs.defineCMacro("VK_ENABLE_BETA_EXTENSIONS", "1");
        engine_c_libs.addIncludeDir(try std.fmt.allocPrint(b.allocator, "{s}/include", .{path}));
    }
    yume.addCSourceFile(.{ .file = b.path("engine/c/vk_mem_alloc.cpp"), .flags = &.{""} });
    yume.addCSourceFile(.{ .file = b.path("engine/c/stb_image.c"), .flags = &.{""} });

    yume.addIncludePath(.{ .cwd_relative = "vendor/vma/" });
    yume.addIncludePath(.{ .cwd_relative = "vendor/stb/" });

    yume.linkLibrary(ufbx_lib);

    const flecs_lib = b.addStaticLibrary(.{
        .name = "flecs",
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .windows) {
        flecs_lib.linkSystemLibrary("ws2_32");
    }
    flecs_lib.root_module.addCMacro("FLECS_NO_CPP", "1");
    if (builtin.mode == .Debug) {
        flecs_lib.root_module.addCMacro("FLECS_SANITIZE", "1");
    }
    flecs_lib.addIncludePath(b.path("vendor/flecs/flecs.h"));
    flecs_lib.addIncludePath(b.path("vendor/flecs/flecs_config.h"));
    flecs_lib.root_module.addCMacro("FLECS_CONFIG_HEADER", "1");
    flecs_lib.linkLibC();
    flecs_lib.addCSourceFiles(.{
        .files = &.{
            "vendor/flecs/flecs.c",
        },
    });

    yume.linkLibrary(flecs_lib);

    const engine_c_mod = engine_c_libs.createModule();
    yume.addImport("clibs", engine_c_mod);

    const editor = b.addExecutable(.{
        .name = "yume editor",
        .root_source_file = b.path("editor/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    engine_c_libs.addIncludeDir("vendor/imgui/");
    engine_c_libs.addIncludeDir("vendor/imguizmo/");
    editor.root_module.addImport("clibs", engine_c_mod);

    if (vk_sdk_path) |path| {
        editor.addIncludePath(.{ .cwd_relative = try std.fmt.allocPrint(b.allocator, "{s}/include", .{path}) });
    }
    editor.addIncludePath(.{ .cwd_relative = "vendor/sdl3/include" });
    editor.addIncludePath(b.path("vendor/vma/"));
    editor.addIncludePath(b.path("vendor/stb/"));
    editor.addIncludePath(b.path("vendor/imgui/"));
    editor.addIncludePath(b.path("vendor/imguizmo/"));

    editor.linkLibCpp();
    editor.root_module.addImport("yume", yume);

    b.installArtifact(editor);

    // Imgui (with cimgui and vulkan + sdl3 backends)
    const imgui_lib = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = target,
        .optimize = optimize,
    });
    if (vk_sdk_path) |path| {
        imgui_lib.addIncludePath(.{ .cwd_relative = try std.fmt.allocPrint(b.allocator, "{s}/include", .{path}) });
    }
    imgui_lib.root_module.addCMacro("IMGUI_USE_LEGACY_CRC32_ADLER", "1");
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

    const imguizmo_lib = b.addStaticLibrary(.{
        .name = "cimguizmo",
        .target = target,
        .optimize = optimize,
    });
    imguizmo_lib.addIncludePath(b.path("vendor/imgui/"));
    imguizmo_lib.addIncludePath(b.path("vendor/imguizmo/"));
    imguizmo_lib.linkLibCpp();
    imguizmo_lib.addCSourceFiles(.{
        .files = &.{
            "vendor/imguizmo/ImGuizmo.cpp",
            // "vendor/imguizmo/GraphEditor.cpp",
            // "vendor/imguizmo/ImCurveEdit.cpp",
            // "vendor/imguizmo/ImGradient.cpp",
            // "vendor/imguizmo/ImSequencer.cpp",
            "vendor/imguizmo/cimguizmo.cpp",
        },
    });

    editor.linkLibrary(imguizmo_lib);

    if (target.result.os.tag == .macos) {
        editor.root_module.addRPathSpecial("@executable_path");
    }

    const run_cmd = b.addRunArtifact(editor);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    try build_all_resources(b, .prefix, "resources", "resources");
    try build_all_shaders(b, .prefix, "shaders", "shaders");
}

fn build_all_resources(
    b: *std.Build,
    installdir: std.Build.InstallDir,
    srcdir: []const u8,
    outdir: []const u8,
) !void {
    const dir = try b.build_root.handle.openDir(srcdir, .{ .iterate = true });

    var file_it = dir.iterate();
    while (try file_it.next()) |entry| {
        const basename = std.fs.path.basename(entry.name);
        const src = try std.fs.path.join(b.allocator, &[_][]const u8{ srcdir, basename });
        const out = try std.fs.path.join(b.allocator, &[_][]const u8{ outdir, basename });
        switch (entry.kind) {
            .file => {
                b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .cwd_relative = src }, installdir, out).step);
            },
            .directory => {
                try build_all_resources(b, installdir, src, out);
            },
            else => {},
        }
    }
}

fn build_all_shaders(
    b: *std.Build,
    installdir: std.Build.InstallDir,
    srcdir: []const u8,
    outdir: []const u8,
) !void {
    const shader_ext = "glsl";
    const built_shader_ext = "spv";

    const shaders_dir = try b.build_root.handle.openDir(srcdir, .{ .iterate = true });

    var file_it = shaders_dir.iterate();
    while (try file_it.next()) |entry| {
        if (entry.kind == .file) {
            const ext = std.fs.path.extension(entry.name);
            if (ext.len > 1 and std.mem.eql(u8, ext[1..], shader_ext)) {
                const basename = std.fs.path.basename(entry.name);
                const name = basename[0 .. basename.len - ext.len];
                std.debug.print("Found shader file to compile: {s}.\n", .{entry.name});
                const src = try std.fmt.allocPrint(b.allocator, "{s}/{s}.{s}", .{ srcdir, name, shader_ext });
                const out = try std.fmt.allocPrint(b.allocator, "{s}/{s}.{s}", .{ outdir, name, built_shader_ext });
                build_shader(b, installdir, src, out);
            }
        }
    }
}

fn build_shader(b: *std.Build, installdir: std.Build.InstallDir, src: []const u8, out: []const u8) void {
    const shader_compilation = b.addSystemCommand(&.{"glslangValidator"});
    shader_compilation.addArg("-V");
    shader_compilation.addArg("-o");
    shader_compilation.stdio = .inherit;
    const output = shader_compilation.addOutputFileArg(out);
    shader_compilation.addFileArg(b.path(src));

    b.getInstallStep().dependOn(&b.addInstallFileWithDir(output, installdir, out).step);
}

fn build_sdl3(b: *std.Build, target: std.Build.ResolvedTarget) struct { lib_path: std.Build.LazyPath } {
    const cmake = b.addSystemCommand(&.{"cmake"});
    cmake.stdio = .inherit;
    cmake.addArg("-B");
    const build_dir = cmake.addOutputDirectoryArg("sdl3-build");
    cmake.addArg("-S");
    cmake.addDirectoryArg(.{ .cwd_relative = "vendor/sdl3" });

    switch (target.result.os.tag) {
        .macos => {
            cmake.addArg("-DCMAKE_OSX_DEPLOYMENT_TARGET=10.11");

            const lib_name = "libSDL3.dylib";
            const lib_sym_name = "libSDL3.0.dylib";
            const make = b.addSystemCommand(&.{"make"});
            make.step.dependOn(&cmake.step);
            make.stdio = .inherit;
            make.addArg("-C");
            make.addDirectoryArg(build_dir);
            make.addArgs(&.{ "-j", b.fmt("{d}", .{std.Thread.getCpuCount() catch 1}) });

            // TODO: This exists because I don't know how to make module directly depend on the final build step,
            // so I have to update the lazy path to enforce it
            const cpy_lib = b.addSystemCommand(&.{"cp"});
            cpy_lib.step.dependOn(&make.step);
            cpy_lib.addDirectoryArg(build_dir.path(b, lib_name));
            const lib_path = cpy_lib.addOutputFileArg(lib_name);

            const cpy_lib_sym = b.addSystemCommand(&.{"cp"});
            cpy_lib_sym.step.dependOn(&cpy_lib.step);
            cpy_lib_sym.addDirectoryArg(build_dir.path(b, lib_name));
            const lib_sym_path = cpy_lib_sym.addOutputFileArg(lib_name);

            var install_lib_step = &b.addInstallBinFile(lib_path, lib_name).step;
            install_lib_step.dependOn(&cpy_lib.step);
            b.getInstallStep().dependOn(install_lib_step);

            var install_lib_sym_step = &b.addInstallBinFile(lib_sym_path, lib_sym_name).step;
            install_lib_sym_step.dependOn(&cpy_lib_sym.step);
            b.getInstallStep().dependOn(install_lib_sym_step);

            return .{ .lib_path = lib_sym_path.dirname() };
        },
        else => unreachable,
    }
}

fn assertTargetSupported(target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        //support platforms
        .windows, .macos => {},
        inline else => |pl| @panic("Unsupported target platform " ++ @tagName(pl)),
    }
}
