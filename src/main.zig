const std = @import("std");
const alsa = @import("alsa.zig");
const xcb = @import("xcb.zig");
const vk = @import("vulkan.zig");

pub fn main() !void {
    // TODO: init configuration system first, then choose other systems based on it; e.g. skipping ui on a dedicated server

    const ui = try xcb.init();
    defer ui.kill();

    const gpu = try vk.init();
    defer gpu.kill();

    const sound = try alsa.init();
    defer sound.kill();

    var should_run = true;

    while (should_run) {
        // handle ui
        while (ui.poll()) |event| {
            switch (event) {
                xcb.UIEvent.Nop => {},
                xcb.UIEvent.Exit => {
                    should_run = false;
                },
            }
        }

        // handle other systems here
    }

    std.debug.print("exit clean\n", .{});
}
