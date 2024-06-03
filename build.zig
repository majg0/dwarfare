const std = @import("std");
const builtin = @import("builtin");

// TODO: create header files
// https://github.com/ziglang/zig/issues/18188#issuecomment-2140880349

pub fn build(b: *std.Build) void {
    const install_step = b.getInstallStep();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const game_only = b.option(
        bool,
        "game_only",
        "Only build the game library, skipping the main executable.",
    ) orelse false;

    // Game
    const lib_name = "game";
    // TODO: handle macOS multiarch like in platform.
    const lib_compile = b.addSharedLibrary(.{
        .name = lib_name,
        .root_source_file = b.path("src/" ++ lib_name ++ ".zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib_install = b.addInstallArtifact(lib_compile, .{});
    install_step.dependOn(&lib_install.step);

    if (game_only) {
        return;
    }

    // Platform core ("dwarven")
    var dwarven: *std.Build.Step.Compile = undefined;
    {
        const platform_name = "dwarven";
        switch (builtin.os.tag) {
            .windows => {
                const compile = b.addStaticLibrary(.{
                    .name = platform_name,
                    .root_source_file = b.path("src/platform/core/lib.zig"),
                    .target = target,
                    .optimize = optimize,
                    .link_libc = true,
                });
                dwarven = compile;

                const install = b.addInstallArtifact(compile, .{});
                install_step.dependOn(&install.step);
            },
            .macos => {
                // aarch64
                var aarch64_target = target;
                aarch64_target.query.cpu_arch = .aarch64;
                const aarch64_compile = b.addStaticLibrary(.{
                    .name = platform_name ++ "_aarch64",
                    .root_source_file = b.path("src/platform/core/lib.zig"),
                    .target = aarch64_target,
                    .optimize = optimize,
                    .link_libc = true,
                });
                aarch64_compile.bundle_compiler_rt = true;

                // x86_64
                var x86_64_target = target;
                x86_64_target.query.cpu_arch = .x86_64;
                const x86_64_compile = b.addStaticLibrary(.{
                    .name = platform_name ++ "_x86_64",
                    .root_source_file = b.path("src/platform/core/lib.zig"),
                    .target = x86_64_target,
                    .optimize = optimize,
                    .link_libc = true,
                });
                x86_64_compile.bundle_compiler_rt = true;

                // universal
                const universal = b.addSystemCommand(&.{ "lipo", "-create", "-output" });
                const universal_file = universal.addOutputFileArg("lib" ++ platform_name ++ ".a");
                universal.addArtifactArg(aarch64_compile);
                universal.addArtifactArg(x86_64_compile);
                universal.step.dependOn(&aarch64_compile.step);
                universal.step.dependOn(&x86_64_compile.step);

                // xcframework
                // NOTE: we imperatively delete + recreate, to delete any stale files in case of renames.
                const xcframework_file = b.path("src/platform/macos/" ++ platform_name ++ ".xcframework");

                const xcframework_delete = b.addSystemCommand(&.{ "rm", "-rf" });
                xcframework_delete.has_side_effects = true;
                xcframework_delete.addFileArg(xcframework_file);

                const xcframework = b.addSystemCommand(&.{ "xcodebuild", "-create-xcframework", "-library" });
                xcframework.has_side_effects = true;
                xcframework.addFileArg(universal_file);
                xcframework.addArg("-headers");
                xcframework.addDirectoryArg(b.path("src/platform/core/include"));
                xcframework.addArg("-output");
                xcframework.addFileArg(xcframework_file);
                xcframework.step.dependOn(&universal.step);
                xcframework.step.dependOn(&xcframework_delete.step);

                const xcframework_install = b.addInstallDirectory(.{
                    .source_dir = xcframework_file,
                    .install_dir = .lib,
                    .install_subdir = platform_name ++ ".xcframework",
                });
                xcframework_install.step.dependOn(&xcframework.step);
                install_step.dependOn(&xcframework_install.step);
            },
            else => unreachable,
        }
    }

    // Platform-dependent executable ("dwarven")
    const exe_name = "dwarven";
    var exe_compile: *std.Build.Step.Compile = undefined;
    {
        switch (builtin.os.tag) {
            .windows => {
                exe_compile = b.addExecutable(.{
                    .name = exe_name,
                    .root_source_file = b.path("src/platform/windows/main.zig"),
                    .target = target,
                    .optimize = optimize,
                    // .link_libc = true,
                });
                exe_compile.addIncludePath(b.path("src/platform/core/include/"));
                exe_compile.linkLibrary(dwarven);
            },
            else => @compileError("can we build the whole shebang for this platform using only zig's build system?"),
        }
    }

    // Main executable
    // const exe_name = "dwarfare";
    // const exe_compile = b.addExecutable(.{
    //     .name = exe_name,
    //     .root_source_file = b.path("src/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    //     .link_libc = true,
    // });
    const exe_install = b.addInstallArtifact(exe_compile, .{});
    install_step.dependOn(&exe_install.step);

    // Target: run
    {
        const exe_run = b.addRunArtifact(exe_compile);
        exe_run.step.dependOn(install_step);

        const exe_step = b.step("run", "Run the main executable.");
        exe_step.dependOn(&exe_run.step);

        if (b.args) |args| {
            exe_run.addArgs(args);
        }
    }

    // Target: test
    {
        const filter: ?[]const u8 =
            if (b.args != null and b.args.?.len == 1) b.args.?[0] else null;

        // Target: test:unit
        const unit_compile = b.addTest(.{
            .name = "test_unit",
            .root_source_file = b.path("src/test_unit.zig"),
            .target = target,
            .optimize = optimize,
            .filter = filter,
        });
        const unit_run = b.addRunArtifact(unit_compile);
        const unit_step = b.step("test:unit", "Run unit tests");
        unit_step.dependOn(&unit_run.step);

        // Target: test:integration
        const integration_compile = b.addTest(.{
            .name = "test_integration",
            .root_source_file = b.path("src/test_integration.zig"),
            .target = target,
            .optimize = optimize,
        });
        const integration_run = b.addRunArtifact(integration_compile);
        // NOTE: ensure we can access the binaries
        integration_run.step.dependOn(install_step);
        const integration_step = b.step("test:integration", "Run integration tests");
        integration_step.dependOn(&integration_run.step);

        const step = b.step("test", "Run all tests, or filter to unit tests with filenames or test names matching the first argument, e.g. `zig build test -- ecs`");
        step.dependOn(&unit_run.step);
        if (filter == null) {
            step.dependOn(&integration_run.step);
        }
    }
}
