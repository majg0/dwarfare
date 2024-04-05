const std = @import("std");
const alsa = @import("alsa.zig");
const xcb = @import("xcb.zig");
const vk = @import("vulkan.zig");

pub fn main() !void {
    // NOTE: this avoids the lack of line break from `zig build run` output
    std.debug.print("\n", .{});

    // TODO: init configuration system first, then choose other systems based on it; e.g. skipping ui on a dedicated server

    const ui = try xcb.init();
    defer ui.kill();

    const gpu = try vk.init();
    defer gpu.kill();

    var sound = try alsa.init();
    defer sound.kill();

    var should_run = true;

    while (should_run) {
        while (ui.poll()) |event| {
            switch (event) {
                xcb.UIEvent.Nop => {},
                xcb.UIEvent.Exit => {
                    should_run = false;
                },
            }
        }

        gpu.update();

        try sound.update();
    }

    std.debug.print("exit clean\n", .{});
}
