const std = @import("std");

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
    const lib_compile = b.addSharedLibrary(.{
        .name = lib_name,
        .root_source_file = b.path("src/" ++ lib_name ++ ".zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = b.addInstallArtifact(lib_compile, .{});
    install_step.dependOn(&lib_compile.step);

    if (game_only) {
        return;
    }

    // Main executable
    const exe_name = "dwarfare";
    const exe_compile = b.addExecutable(.{
        .name = exe_name,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    _ = b.addInstallArtifact(exe_compile, .{});
    install_step.dependOn(&exe_compile.step);

    // Target: run
    {
        const exe_run = b.addRunArtifact(exe_compile);
        exe_run.step.dependOn(install_step);

        const exe_step = b.step("run", "Run the main executable.");
        exe_step.dependOn(&exe_run.step);
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
