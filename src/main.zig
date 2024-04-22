const std = @import("std");
const alsa = @import("alsa.zig");
const xcb = @import("xcb.zig");
const vk = @import("vulkan.zig");
const inp = @import("input.zig");
const Timer = @import("Timer.zig");
const CircularBuffer = @import("CircularBuffer.zig");

const State = struct {
    timer_update: Timer,
    ui: xcb.XcbUi,
    gpu: vk.Vulkan,
    sound: alsa.Alsa,
};

const Action = enum(u8) {
    exit,
    c4on,
    c4off,
    cs4on,
    cs4off,
    d4on,
    d4off,
    ds4on,
    ds4off,
    e4on,
    e4off,
    f4on,
    f4off,
    fs4on,
    fs4off,
    g4on,
    g4off,
    gs4on,
    gs4off,
    a4on,
    a4off,
    as4on,
    as4off,
    b4on,
    b4off,
    c5on,
    c5off,
    octave_prev,
    octave_next,
    recording_start,
    recording_stop,
    recording_playback,
    max_invalid,
};

const FrameEvent = union(enum) {
    start: u64,
    tick: u64,
    action: Action,
};

const ActionBinding = inp.Binding(Action);

const Actions = struct {
    const count: usize = @intFromEnum(Action.max_invalid);

    bindings: [count]ActionBinding,

    pub fn init() Actions {
        var self = Actions{ .bindings = undefined };
        for (&self.bindings, 0..) |*binding, index| {
            binding.* = ActionBinding.init(@enumFromInt(index), .none, .none);
        }
        return self;
    }

    pub fn check(self: *Actions, action: Action, input: inp.Input) bool {
        return self.bindings[@intFromEnum(action)].check(input);
    }

    pub fn bind(self: *Actions, action: Action, predicate: inp.Predicate) void {
        self.bindings[@intFromEnum(action)].main = predicate;
    }

    pub fn bindAlt(self: *Actions, action: Action, predicate: inp.Predicate) void {
        self.bindings[@intFromEnum(action)].alt = predicate;
    }
};

const Recording = struct {
    const RecordingState = enum {
        off,
        recording,
        playing,
    };

    action_buffer: CircularBuffer.CircularBuffer(FrameEvent, 1024),
    state: RecordingState,
    playback_tick_offset: u64,

    pub fn init() Recording {
        var self: Recording = undefined;
        self.action_buffer.init();
        self.state = .off;
        self.playback_tick_offset = 0;
        return self;
    }
};

pub fn main() !void {
    std.debug.print("\n=== Dwarfare ===\n", .{});

    var actions = Actions.init();

    blk: {
        if (std.fs.cwd().openFileZ("input.dat", .{})) |file| {
            defer file.close();
            const size_bytes = try file.readAll(std.mem.asBytes(&actions));
            if (size_bytes == @sizeOf(Actions)) {
                break :blk;
            }
        } else |_| {}
        {
            const phys = inp.phys;
            actions.bind(.exit, phys(9, .press));
            actions.bindAlt(.exit, .{ .wm = .{ .event = .delete } });
            actions.bind(.c4on, phys(38, .press));
            actions.bind(.c4off, phys(38, .release));
            actions.bind(.cs4on, phys(25, .press));
            actions.bind(.cs4off, phys(25, .release));
            actions.bind(.d4on, phys(39, .press));
            actions.bind(.d4off, phys(39, .release));
            actions.bind(.ds4on, phys(26, .press));
            actions.bind(.ds4off, phys(26, .release));
            actions.bind(.e4on, phys(40, .press));
            actions.bind(.e4off, phys(40, .release));
            actions.bind(.f4on, phys(41, .press));
            actions.bind(.f4off, phys(41, .release));
            actions.bind(.fs4on, phys(28, .press));
            actions.bind(.fs4off, phys(28, .release));
            actions.bind(.g4on, phys(42, .press));
            actions.bind(.g4off, phys(42, .release));
            actions.bind(.gs4on, phys(29, .press));
            actions.bind(.gs4off, phys(29, .release));
            actions.bind(.a4on, phys(43, .press));
            actions.bind(.a4off, phys(43, .release));
            actions.bind(.as4on, phys(30, .press));
            actions.bind(.as4off, phys(30, .release));
            actions.bind(.b4on, phys(44, .press));
            actions.bind(.b4off, phys(44, .release));
            actions.bind(.c5on, phys(45, .press));
            actions.bind(.c5off, phys(45, .release));
            actions.bind(.octave_prev, phys(24, .press));
            actions.bind(.octave_next, phys(27, .press));
            actions.bind(.recording_start, phys(10, .press));
            actions.bind(.recording_stop, phys(10, .press));
            actions.bind(.recording_playback, phys(65, .press));

            try std.fs.cwd().writeFile2(.{
                .sub_path = "input.dat",
                .data = std.mem.asBytes(&actions),
                .flags = .{},
            });
        }
    }

    var state: State = undefined;
    try Timer.init(&state.timer_update, 60);

    state.ui = xcb.XcbUi{};
    try state.ui.init();
    defer state.ui.kill();

    state.gpu = vk.Vulkan{};
    try state.gpu.init(state.ui);
    defer state.gpu.kill();

    state.sound = try alsa.init();
    defer state.sound.kill();

    state.sound.master_volume = 0.5;

    var input = inp.Input{};

    var octave: f64 = 1;

    const KeyVoices = struct {
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
    var key_voices = KeyVoices{};

    var recording = Recording.init();

    loop: while (true) {
        // 1. read events while converting into actions
        state.ui.eventsPoll(&input);

        try state.timer_update.accumulate_duration();
        while (state.timer_update.canTick()) {
            // 2. read actions
            defer input.frameConsume();
            defer state.timer_update.tick();

            if (actions.check(.exit, input)) {
                break :loop;
            }

            // state transition
            switch (recording.state) {
                .off => {
                    if (actions.check(.recording_start, input)) {
                        recording.state = .recording;
                        std.debug.print("recording started\n", .{});
                        try recording.action_buffer.write(.{ .start = state.timer_update.frame_index });
                    }
                    if (actions.check(.recording_playback, input)) {
                        recording.state = .playing;
                        recording.action_buffer.head_r = 0;
                        std.debug.print("test {any}", .{recording.action_buffer.value[0..128]});
                        std.debug.print("recording playback started\n", .{});
                    }
                },
                .recording => {
                    if (actions.check(.recording_stop, input)) {
                        recording.state = .off;
                        std.debug.print("recording stopped\n", .{});
                    }
                },
                else => {},
            }

            // state evaluate
            switch (recording.state) {
                .recording => {
                    const tick = .{ .tick = state.timer_update.frame_index };
                    if (recording.action_buffer.peek_w()) |event| {
                        if (event != .tick) {
                            recording.action_buffer.write(tick) catch {
                                recording.state = .off;
                                std.debug.print("recording stopped\n", .{});
                            };
                        } else {
                            try recording.action_buffer.rewrite(tick);
                        }
                    }
                    for (actions.bindings) |binding| {
                        // TODO: turning the action enum into a union(enum) could help against `and`s here; consider size implications
                        if (binding.check(input) and
                            binding.action != .recording_start and
                            binding.action != .recording_stop and
                            binding.action != .recording_playback)
                        {
                            try recording.action_buffer.write(.{ .action = binding.action });
                            std.debug.print("recording {}\n", .{binding.action});
                        }
                    }
                },
                .playing => {
                    blk: {
                        while (recording.action_buffer.peek()) |event| {
                            switch (event) {
                                .start => |tick| {
                                    recording.playback_tick_offset = state.timer_update.frame_index - tick;
                                    try recording.action_buffer.consume();
                                },
                                .tick => |tick| {
                                    if (state.timer_update.frame_index - recording.playback_tick_offset != tick) {
                                        // not ready
                                        break :blk;
                                    }
                                    try recording.action_buffer.consume();
                                    std.debug.print("t{} f{} o{}\n", .{ tick, state.timer_update.frame_index, recording.playback_tick_offset });
                                    // keep reading this frame
                                },
                                .action => |action| {
                                    std.debug.print("action {any}\n", .{action});
                                    switch (action) {
                                        .c4on => key_voices.c4 = state.sound.synth.voice_start(261.63 * octave),
                                        .c4off => state.sound.synth.voice_end(key_voices.c4),
                                        else => {},
                                    }
                                    try recording.action_buffer.consume();
                                },
                            }
                        }

                        recording.state = .off;
                        std.debug.print("recording playback stopped\n", .{});
                    }
                },
                else => {},
            }

            for (actions.bindings) |binding| {
                if (binding.check(input)) {
                    std.debug.print("f{}\n", .{state.timer_update.frame_index});
                    switch (binding.action) {
                        .c4on => key_voices.c4 = state.sound.synth.voice_start(261.63 * octave),
                        .c4off => state.sound.synth.voice_end(key_voices.c4),
                        .cs4on => key_voices.cs4 = state.sound.synth.voice_start(277.18 * octave),
                        .cs4off => state.sound.synth.voice_end(key_voices.cs4),
                        .d4on => key_voices.d4 = state.sound.synth.voice_start(293.66 * octave),
                        .d4off => state.sound.synth.voice_end(key_voices.d4),
                        .ds4on => key_voices.ds4 = state.sound.synth.voice_start(311.13 * octave),
                        .ds4off => state.sound.synth.voice_end(key_voices.ds4),
                        .e4on => key_voices.e4 = state.sound.synth.voice_start(329.63 * octave),
                        .e4off => state.sound.synth.voice_end(key_voices.e4),
                        .f4on => key_voices.f4 = state.sound.synth.voice_start(349.23 * octave),
                        .f4off => state.sound.synth.voice_end(key_voices.f4),
                        .fs4on => key_voices.fs4 = state.sound.synth.voice_start(369.99 * octave),
                        .fs4off => state.sound.synth.voice_end(key_voices.fs4),
                        .g4on => key_voices.g4 = state.sound.synth.voice_start(392.00 * octave),
                        .g4off => state.sound.synth.voice_end(key_voices.g4),
                        .gs4on => key_voices.gs4 = state.sound.synth.voice_start(415.30 * octave),
                        .gs4off => state.sound.synth.voice_end(key_voices.gs4),
                        .a4on => key_voices.a4 = state.sound.synth.voice_start(440.00 * octave),
                        .a4off => state.sound.synth.voice_end(key_voices.a4),
                        .as4on => key_voices.as4 = state.sound.synth.voice_start(466.16 * octave),
                        .as4off => state.sound.synth.voice_end(key_voices.as4),
                        .b4on => key_voices.b4 = state.sound.synth.voice_start(493.88 * octave),
                        .b4off => state.sound.synth.voice_end(key_voices.b4),
                        .c5on => key_voices.c5 = state.sound.synth.voice_start(523.25 * octave),
                        .c5off => state.sound.synth.voice_end(key_voices.c5),
                        .octave_prev => octave *= 0.5,
                        .octave_next => octave *= 2,
                        else => {},
                    }
                }
            }
        }

        if ((input.wm.flags & @intFromEnum(inp.Input.Wm.Event.resize)) != 0) {
            try state.gpu.swapchainInit(false);
        }

        try state.gpu.frameDraw();

        try state.sound.update();
    }

    std.debug.print("exited cleanly\n", .{});
}
