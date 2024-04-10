const std = @import("std");
const alsa = @import("alsa.zig");
const xcb = @import("xcb.zig");
const vk = @import("vulkan.zig");

const Action = enum(u8) {
    exit,
};

const Bindings = struct {
    main: struct {
        exit: xcb.Binding,
    },
};

pub fn main() !void {
    // NOTE: this avoids the lack of line break from `zig build run` output
    std.debug.print("\n=== Dwarfare ===\n", .{});

    // TODO: init configuration system first, then choose other systems based on it; e.g. skipping ui on a dedicated server

    const input = blk: {
        if (std.fs.cwd().openFileZ("input.dat", .{})) |file| {
            defer file.close();
            var binding: Bindings = undefined;
            const size = try file.readAll(std.mem.asBytes(&binding));
            std.debug.assert(size == @sizeOf(Bindings));
            break :blk binding;
        } else |_| {
            const binding = Bindings{
                .main = .{
                    .exit = .{
                        .main = .{
                            .physical = .{
                                .event = .press,
                                .key = .esc,
                            },
                        },
                        .alt = .{
                            .wm = .{ .event = .delete_window },
                        },
                    },
                },
            };

            try std.fs.cwd().writeFile2(.{
                .sub_path = "input.dat",
                .data = std.mem.asBytes(&binding),
                .flags = .{},
            });

            break :blk binding;
        }
    };

    var ui = try xcb.init();
    defer ui.kill();

    const gpu = try vk.init();
    defer gpu.kill();

    var sound = try alsa.init();
    defer sound.kill();

    sound.master_volume = 0;

    var should_run = true;

    while (should_run) {
        ui.update();

        if (input.main.exit.check(ui)) {
            should_run = false;
            break;
        }

        gpu.update();

        try sound.update();
    }

    std.debug.print("exit clean\n", .{});
}
