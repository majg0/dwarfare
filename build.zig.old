const std = @import("std");

const name = "dwarfare";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // NOTE: `zig build` target
    {
        const install_step = b.getInstallStep();

        // NOTE: compile shaders
        {
            const runs: [2]*std.Build.Step.Run = .{
                b.addSystemCommand(&.{
                    "glslc",
                    "shaders/shader.vert",
                    "-o",
                    "shaders/shader.vert.spv",
                }),
                b.addSystemCommand(&.{
                    "glslc",
                    "shaders/shader.frag",
                    "-o",
                    "shaders/shader.frag.spv",
                }),
            };
            for (runs) |run| {
                install_step.dependOn(&run.step);
            }
        }

        // NOTE: exe
        {
            const exe_compile = b.addExecutable(.{
                .name = name,
                .root_source_file = .{ .path = "src/main.zig" },
                .target = target,
                .optimize = optimize,
            });

            // NOTE: exe link
            {
                exe_compile.linkLibC();
                exe_compile.linkSystemLibrary("xcb");
                exe_compile.linkSystemLibrary("xcb-xkb");
                exe_compile.linkSystemLibrary("xkbcommon");
                exe_compile.linkSystemLibrary("xkbcommon-x11");
                exe_compile.linkSystemLibrary("vulkan");
                exe_compile.linkSystemLibrary("asound");
            }

            // NOTE: exe install
            {
                const exe_install = b.addInstallArtifact(exe_compile, .{});
                install_step.dependOn(&exe_install.step);
            }

            // NOTE: `zig build run` target
            {
                const exe_run = b.addRunArtifact(exe_compile);
                exe_run.step.dependOn(install_step);
                if (b.args) |args| {
                    exe_run.addArgs(args);
                }
                const run_step = b.step("run", "Run the app");
                run_step.dependOn(&exe_run.step);
            }
        }

        // NOTE: static lib
        {
            const lib_compile = b.addStaticLibrary(.{
                .name = name,
                .root_source_file = .{ .path = "src/root.zig" },
                .target = target,
                .optimize = optimize,
            });

            // NOTE: lib install
            {
                const lib_install = b.addInstallArtifact(lib_compile, .{});
                install_step.dependOn(&lib_install.step);
            }
        }
    }

    // NOTE: `zig build test` target
    {
        const test_compile = b.addTest(.{
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });

        const test_run = b.addRunArtifact(test_compile);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&test_run.step);
    }
}
