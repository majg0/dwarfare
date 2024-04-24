const std = @import("std");
const alsa = @import("alsa.zig");
const xcb = @import("xcb.zig");
const vk = @import("vulkan.zig");
const inp = @import("input.zig");
const Timer = @import("Timer.zig");
const CircularBuffer = @import("CircularBuffer.zig");

const InputBindings = inp.InputBindings(Action);

const State = struct {
    timer_update: Timer,
    ui: xcb.XcbUi,
    gpu: vk.Vulkan,
    sound: alsa.Alsa,
    bindings: InputBindings,
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
    max_invalid,
};

const FrameEvent = union(enum) {
    tick: u64,
    action: Action,
};

const Recorder = struct {
    action_buffer: CircularBuffer.CircularBuffer(FrameEvent, 1024),
    playback_tick_offset: u64,
    file: std.fs.File,

    pub fn init(recording: std.fs.File) Recorder {
        var self: Recorder = undefined;
        self.action_buffer.init();
        const bytes = recording.readAll(std.mem.asBytes(&self.action_buffer.value)) catch 0;
        self.action_buffer.head_w = bytes / @sizeOf(FrameEvent);
        self.action_buffer.tail = bytes / @sizeOf(FrameEvent);
        self.playback_tick_offset = 0;
        self.file = recording;
        return self;
    }

    pub fn frame_write(self: *Recorder, frame_index: u64, bindings: InputBindings, input: inp.Input) (error{ Empty, Full } || std.fs.File.WriteError)!void {
        var wrote = false;
        for (bindings.actions) |binding| {
            if (binding.check(input)) {
                if (wrote == false) {
                    try self.action_buffer.write(.{ .tick = frame_index });
                    wrote = true;
                }
                std.debug.print("action {}\n", .{binding.action});
                try self.action_buffer.write(.{ .action = binding.action });
            }
        }
        if (wrote) {
            try self.action_buffer.flush(self.file);
        }
    }

    pub fn frame_advance(self: *Recorder, frame_index: u64) ?FrameEvent {
        if (self.action_buffer.peek(0)) |event| {
            switch (event) {
                .tick => |tick| {
                    if (frame_index == tick + self.playback_tick_offset) {
                        if (self.action_buffer.peek(1)) |next| {
                            if (next != .tick) {
                                self.action_buffer.consume();
                                self.action_buffer.consume();
                                return next;
                            }
                        }
                    }
                    return null;
                },
                .action => {
                    self.action_buffer.consume();
                    return event;
                },
            }
        }
        return null;
    }
};

pub fn main() !void {
    std.debug.print("\n=== Dwarfare ===\n", .{});

    var state: State = undefined;

    blk: {
        if (std.fs.cwd().openFileZ("input.dat", .{})) |file| {
            defer file.close();
            const size_bytes = try file.readAll(std.mem.asBytes(&state.bindings));
            if (size_bytes == @sizeOf(InputBindings)) {
                break :blk;
            }
        } else |_| {}
        {
            state.bindings.init();
            const phys = inp.phys;
            state.bindings.bind(.exit, phys(9, .press));
            state.bindings.bindAlt(.exit, .{ .wm = .{ .event = .delete } });
            state.bindings.bind(.c4on, phys(38, .press));
            state.bindings.bind(.c4off, phys(38, .release));
            state.bindings.bind(.cs4on, phys(25, .press));
            state.bindings.bind(.cs4off, phys(25, .release));
            state.bindings.bind(.d4on, phys(39, .press));
            state.bindings.bind(.d4off, phys(39, .release));
            state.bindings.bind(.ds4on, phys(26, .press));
            state.bindings.bind(.ds4off, phys(26, .release));
            state.bindings.bind(.e4on, phys(40, .press));
            state.bindings.bind(.e4off, phys(40, .release));
            state.bindings.bind(.f4on, phys(41, .press));
            state.bindings.bind(.f4off, phys(41, .release));
            state.bindings.bind(.fs4on, phys(28, .press));
            state.bindings.bind(.fs4off, phys(28, .release));
            state.bindings.bind(.g4on, phys(42, .press));
            state.bindings.bind(.g4off, phys(42, .release));
            state.bindings.bind(.gs4on, phys(29, .press));
            state.bindings.bind(.gs4off, phys(29, .release));
            state.bindings.bind(.a4on, phys(43, .press));
            state.bindings.bind(.a4off, phys(43, .release));
            state.bindings.bind(.as4on, phys(30, .press));
            state.bindings.bind(.as4off, phys(30, .release));
            state.bindings.bind(.b4on, phys(44, .press));
            state.bindings.bind(.b4off, phys(44, .release));
            state.bindings.bind(.c5on, phys(45, .press));
            state.bindings.bind(.c5off, phys(45, .release));
            state.bindings.bind(.octave_prev, phys(24, .press));
            state.bindings.bind(.octave_next, phys(27, .press));

            try std.fs.cwd().writeFile2(.{
                .sub_path = "input.dat",
                .data = std.mem.asBytes(&state.bindings),
                .flags = .{},
            });
        }
    }

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

    // TODO: use app data folder instead
    try std.fs.cwd().makePath("recordings");
    const recording = try std.fs.cwd().createFile(
        "recordings/test.rec",
        .{ .read = true, .truncate = false },
    );
    var recorder = Recorder.init(recording);

    loop: while (true) {
        state.ui.eventsPoll(&input);

        try state.timer_update.accumulate_duration();
        while (state.timer_update.canTick()) {
            std.debug.print("--- frame {} ---\n", .{state.timer_update.frame_index});
            defer input.frameConsume();
            defer state.timer_update.tick();

            if (state.bindings.check(.exit, input)) {
                break :loop;
            }

            try recorder.frame_write(state.timer_update.frame_index, state.bindings, input);

            while (recorder.frame_advance(state.timer_update.frame_index)) |event| {
                std.debug.print("{any}\n", .{event});
                if (event != .action) {
                    continue;
                }
                const action = event.action;
                switch (action) {
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

        if ((input.wm.flags & @intFromEnum(inp.Input.Wm.Event.resize)) != 0) {
            try state.gpu.swapchainInit(false);
        }

        try state.gpu.frameDraw();

        try state.sound.update();
    }

    std.debug.print("exited cleanly\n", .{});
}
