const std = @import("std");

const Mode = enum {
    Full,
    LibOnly,
    ExeOnly,
};

pub fn build(b: *std.Build) void {
    const install_step = b.getInstallStep();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mode = b.option(
        Mode,
        "mode",
        "Whether to build the game library, the host executable, or both.",
    ) orelse .Full;

    if (mode == .Full or mode == .ExeOnly) {
        const exe_compile = b.addExecutable(.{
            .name = "dwarfare",
            .root_source_file = b.path("src/platform.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        b.installArtifact(exe_compile);

        const run_exe = b.addRunArtifact(exe_compile);

        run_exe.step.dependOn(install_step);
        const run_step = b.step("run", "Run the application");
        run_step.dependOn(&run_exe.step);
    }

    if (mode == .Full or mode == .LibOnly) {
        const lib_compile = b.addSharedLibrary(.{
            .name = "dwarfare",
            .root_source_file = b.path("src/dwarfare.zig"),
            .target = target,
            .optimize = optimize,
        });

        b.installArtifact(lib_compile);
    }
}
