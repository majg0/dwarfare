const std = @import("std");
const alsa = @import("alsa.zig");
const xcb = @import("xcb.zig");
const vk = @import("vulkan.zig");
const inp = @import("input.zig");

const Action = enum(u8) {
    exit,
};

const Bindings = struct {
    main: struct {
        exit: inp.Binding,
        play: struct {
            c4: inp.Binding,
            cs4: inp.Binding,
            d4: inp.Binding,
            ds4: inp.Binding,
            e4: inp.Binding,
            f4: inp.Binding,
            fs4: inp.Binding,
            g4: inp.Binding,
            gs4: inp.Binding,
            a4: inp.Binding,
            as4: inp.Binding,
            b4: inp.Binding,
            c5: inp.Binding,
            octave_prev: inp.Binding,
            octave_next: inp.Binding,
        },
    },
};

fn play(key: u8) inp.Binding {
    return .{
        .main = .{ .physical = .{ .event = .press, .key = key } },
        .alt = .{ .none = .{} },
    };
}

pub fn main() !void {
    // NOTE: this avoids the lack of line break from `zig build run` output
    std.debug.print("\n=== Dwarfare ===\n", .{});

    // TODO: init configuration system first, then choose other systems based on it; e.g. skipping ui on a dedicated server

    const bindings = blk: {
        if (std.fs.cwd().openFileZ("input.dat", .{})) |file| {
            defer file.close();
            var binding: Bindings = undefined;
            const size = try file.readAll(std.mem.asBytes(&binding));
            if (size == @sizeOf(Bindings)) {
                break :blk binding;
            }
        } else |_| {}
        {
            const binding = Bindings{
                .main = .{
                    .exit = .{
                        .main = .{ .physical = .{ .event = .press, .key = 9 } },
                        .alt = .{ .wm = .{ .event = .delete } },
                    },
                    .play = .{
                        .c4 = play(38),
                        .cs4 = play(25),
                        .d4 = play(39),
                        .ds4 = play(26),
                        .e4 = play(40),
                        .f4 = play(41),
                        .fs4 = play(28),
                        .g4 = play(42),
                        .gs4 = play(29),
                        .a4 = play(43),
                        .as4 = play(30),
                        .b4 = play(44),
                        .c5 = play(45),
                        .octave_prev = play(24),
                        .octave_next = play(27),
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

    var ui = xcb.XcbUi{};
    try ui.init();
    defer ui.kill();

    var gpu = vk.Vulkan{};
    try gpu.init(ui);
    defer gpu.kill();

    var sound = try alsa.init();
    defer sound.kill();

    sound.master_volume = 0.5;

    var should_run = true;

    var input = inp.Input{};

    std.debug.print("\n=== Start ===\n", .{});

    var octave: f64 = 1;

    while (should_run) {
        defer input.frameConsume();
        ui.eventsPoll(&input);

        if (bindings.main.exit.check(input)) {
            should_run = false;
            break;
        }

        if (bindings.main.play.c4.check(input)) {
            // const freq_base = 440;
            // const octave_size = 2;
            // const index = 3;
            // var scale: [12]f64 = undefined;
            // inline for (&scale, 0..) |*step, i| {
            //     const len: f64 = @floatFromInt(scale.len);
            //     const ind: f64 = @floatFromInt(i);
            //     step.* = ind / len;
            // }
            // const offset: f64 = @floatFromInt(index / scale.len);
            // sound.freq = freq_base * std.math.pow(f64, octave_size, offset + scale[index % scale.len]);
            sound.synth.voice.frequency = 261.63 * octave;
        }
        if (bindings.main.play.cs4.check(input)) {
            sound.synth.voice.frequency = 277.18 * octave;
        }
        if (bindings.main.play.d4.check(input)) {
            sound.synth.voice.frequency = 293.66 * octave;
        }
        if (bindings.main.play.ds4.check(input)) {
            sound.synth.voice.frequency = 311.13 * octave;
        }
        if (bindings.main.play.e4.check(input)) {
            sound.synth.voice.frequency = 329.63 * octave;
        }
        if (bindings.main.play.f4.check(input)) {
            sound.synth.voice.frequency = 349.23 * octave;
        }
        if (bindings.main.play.fs4.check(input)) {
            sound.synth.voice.frequency = 369.99 * octave;
        }
        if (bindings.main.play.g4.check(input)) {
            sound.synth.voice.frequency = 392.00 * octave;
        }
        if (bindings.main.play.gs4.check(input)) {
            sound.synth.voice.frequency = 415.30 * octave;
        }
        if (bindings.main.play.a4.check(input)) {
            sound.synth.voice.frequency = 440.00 * octave;
        }
        if (bindings.main.play.as4.check(input)) {
            sound.synth.voice.frequency = 466.16 * octave;
        }
        if (bindings.main.play.b4.check(input)) {
            sound.synth.voice.frequency = 493.88 * octave;
        }
        if (bindings.main.play.c5.check(input)) {
            sound.synth.voice.frequency = 523.25 * octave;
        }
        if (bindings.main.play.octave_prev.check(input)) {
            octave *= 0.5;
        }
        if (bindings.main.play.octave_next.check(input)) {
            octave *= 2;
        }

        if ((input.wm.flags & @intFromEnum(inp.Input.Wm.Event.resize)) != 0) {
            try gpu.swapchainInit();
        }

        try gpu.frameDraw();

        try sound.update();
    }

    std.debug.print("exited cleanly\n", .{});
}
