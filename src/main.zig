const std = @import("std");
const alsa = @import("alsa.zig");
const xcb = @import("xcb.zig");
const vk = @import("vulkan.zig");

pub fn main() !void {
    // NOTE: this avoids the lack of line break from `zig build run` output
    std.debug.print("\n", .{});

    // TODO: init configuration system first, then choose other systems based on it; e.g. skipping ui on a dedicated server

    var ui = try xcb.init();
    defer ui.kill();

    const gpu = try vk.init();
    defer gpu.kill();

    var sound = try alsa.init();
    defer sound.kill();

    sound.master_volume = 0;

    var should_run = true;

    while (should_run) {
        while (ui.poll()) |event| {
            switch (event) {
                xcb.UIEvent.Nop => {},
                xcb.UIEvent.KeysChanged => {},
                xcb.UIEvent.Exit => {
                    should_run = false;
                },
            }
        }

        if (ui.keys.pressed(1)) {
            std.debug.print("LMB!\n", .{});
        }
        if (ui.keys.pressed(9)) {
            std.debug.print("Esc!\n", .{});
            should_run = false;
            break;
        }

        ui.update();

        gpu.update();

        try sound.update();
    }

    std.debug.print("exit clean\n", .{});
}
