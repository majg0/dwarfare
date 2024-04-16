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
            c4on: inp.Binding,
            c4off: inp.Binding,
            cs4on: inp.Binding,
            cs4off: inp.Binding,
            d4on: inp.Binding,
            d4off: inp.Binding,
            ds4on: inp.Binding,
            ds4off: inp.Binding,
            e4on: inp.Binding,
            e4off: inp.Binding,
            f4on: inp.Binding,
            f4off: inp.Binding,
            fs4on: inp.Binding,
            fs4off: inp.Binding,
            g4on: inp.Binding,
            g4off: inp.Binding,
            gs4on: inp.Binding,
            gs4off: inp.Binding,
            a4on: inp.Binding,
            a4off: inp.Binding,
            as4on: inp.Binding,
            as4off: inp.Binding,
            b4on: inp.Binding,
            b4off: inp.Binding,
            c5on: inp.Binding,
            c5off: inp.Binding,
            octave_prev: inp.Binding,
            octave_next: inp.Binding,
        },
    },
};

fn key(id: u8, event: inp.KeyEvent) inp.Binding {
    return .{
        .main = .{ .physical = .{ .event = event, .key = id } },
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
                        .c4on = key(38, .press),
                        .c4off = key(38, .release),
                        .cs4on = key(25, .press),
                        .cs4off = key(25, .release),
                        .d4on = key(39, .press),
                        .d4off = key(39, .release),
                        .ds4on = key(26, .press),
                        .ds4off = key(26, .release),
                        .e4on = key(40, .press),
                        .e4off = key(40, .release),
                        .f4on = key(41, .press),
                        .f4off = key(41, .release),
                        .fs4on = key(28, .press),
                        .fs4off = key(28, .release),
                        .g4on = key(42, .press),
                        .g4off = key(42, .release),
                        .gs4on = key(29, .press),
                        .gs4off = key(29, .release),
                        .a4on = key(43, .press),
                        .a4off = key(43, .release),
                        .as4on = key(30, .press),
                        .as4off = key(30, .release),
                        .b4on = key(44, .press),
                        .b4off = key(44, .release),
                        .c5on = key(45, .press),
                        .c5off = key(45, .release),
                        .octave_prev = key(24, .press),
                        .octave_next = key(27, .press),
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

    var octave: f64 = 1;

    const KeyState = struct {
        c4: usize = 0,
        cs4: usize = 0,
        d4: usize = 0,
        ds4: usize = 0,
        e4: usize = 0,
        f4: usize = 0,
        fs4: usize = 0,
        g4: usize = 0,
        gs4: usize = 0,
        a4: usize = 0,
        as4: usize = 0,
        b4: usize = 0,
        c5: usize = 0,
    };
    var key_state = KeyState{};

    while (should_run) {
        defer input.frameConsume();
        ui.eventsPoll(&input);

        if (bindings.main.exit.check(input)) {
            should_run = false;
            break;
        }

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
        if (bindings.main.play.c4on.check(input)) key_state.c4 = sound.synth.voice_start(261.63 * octave);
        if (bindings.main.play.c4off.check(input)) sound.synth.voice_end(key_state.c4);
        if (bindings.main.play.cs4on.check(input)) key_state.cs4 = sound.synth.voice_start(277.18 * octave);
        if (bindings.main.play.cs4off.check(input)) sound.synth.voice_end(key_state.cs4);
        if (bindings.main.play.d4on.check(input)) key_state.d4 = sound.synth.voice_start(293.66 * octave);
        if (bindings.main.play.d4off.check(input)) sound.synth.voice_end(key_state.d4);
        if (bindings.main.play.ds4on.check(input)) key_state.ds4 = sound.synth.voice_start(311.13 * octave);
        if (bindings.main.play.ds4off.check(input)) sound.synth.voice_end(key_state.ds4);
        if (bindings.main.play.e4on.check(input)) key_state.e4 = sound.synth.voice_start(329.63 * octave);
        if (bindings.main.play.e4off.check(input)) sound.synth.voice_end(key_state.e4);
        if (bindings.main.play.f4on.check(input)) key_state.f4 = sound.synth.voice_start(349.23 * octave);
        if (bindings.main.play.f4off.check(input)) sound.synth.voice_end(key_state.f4);
        if (bindings.main.play.fs4on.check(input)) key_state.fs4 = sound.synth.voice_start(369.99 * octave);
        if (bindings.main.play.fs4off.check(input)) sound.synth.voice_end(key_state.fs4);
        if (bindings.main.play.g4on.check(input)) key_state.g4 = sound.synth.voice_start(392.00 * octave);
        if (bindings.main.play.g4off.check(input)) sound.synth.voice_end(key_state.g4);
        if (bindings.main.play.gs4on.check(input)) key_state.gs4 = sound.synth.voice_start(415.30 * octave);
        if (bindings.main.play.gs4off.check(input)) sound.synth.voice_end(key_state.gs4);
        if (bindings.main.play.a4on.check(input)) key_state.a4 = sound.synth.voice_start(440.00 * octave);
        if (bindings.main.play.a4off.check(input)) sound.synth.voice_end(key_state.a4);
        if (bindings.main.play.as4on.check(input)) key_state.as4 = sound.synth.voice_start(466.16 * octave);
        if (bindings.main.play.as4off.check(input)) sound.synth.voice_end(key_state.as4);
        if (bindings.main.play.b4on.check(input)) key_state.b4 = sound.synth.voice_start(493.88 * octave);
        if (bindings.main.play.b4off.check(input)) sound.synth.voice_end(key_state.b4);
        if (bindings.main.play.c5on.check(input)) key_state.c5 = sound.synth.voice_start(523.25 * octave);
        if (bindings.main.play.c5off.check(input)) sound.synth.voice_end(key_state.c5);
        if (bindings.main.play.octave_prev.check(input)) octave *= 0.5;
        if (bindings.main.play.octave_next.check(input)) octave *= 2;

        if ((input.wm.flags & @intFromEnum(inp.Input.Wm.Event.resize)) != 0) {
            try gpu.swapchainInit();
        }

        try gpu.frameDraw();

        try sound.update();
    }

    std.debug.print("exited cleanly\n", .{});
}
