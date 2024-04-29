const std = @import("std");
const cli = @import("cli.zig");
const alsa = @import("alsa.zig");
const xcb = @import("xcb.zig");
const vk = @import("vulkan.zig");
const inp = @import("input.zig");
const Timer = @import("Timer.zig");
const CircularBuffer = @import("CircularBuffer.zig");

const assert = std.debug.assert;

const InputBindings = inp.InputBindings(Action);

const Systems = struct {
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

const CliConfig = union(enum) {
    pub const help = std.fmt.comptimePrint(
        \\
        \\ Dwarfare ({[version]d})
        \\ Martin Grönlund <martingronlund@live.se>
        \\
        \\ dwarfare <scope> <command> [parameters]
        \\   game
        \\     run              Open the game in the default user menu
        \\
        \\   dedicated
        \\     run              Run a dedicated server
        \\       --port=<port>  Port to watch for connections on
        \\                      Defaults to {[port]d}
        \\
        \\   replay
        \\     run              Watch a replay file
        \\       --path=<path>  Path to replay file
        \\
    , .{
        .version = 0.1,
        .port = 1337,
    });

    game: union(enum) {
        run: struct {},
    },
    dedicated: union(enum) {
        run: struct {},
    },
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const config = cli.parse(&args, CliConfig) orelse CliConfig{
        .game = .{
            .run = .{},
        },
    };

    switch (config) {
        .game => {},
        .dedicated => unreachable,
    }

    var sys: Systems = undefined;

    blk: {
        if (std.fs.cwd().openFileZ("input.dat", .{})) |file| {
            defer file.close();
            const size_bytes = try file.readAll(std.mem.asBytes(&sys.bindings));
            if (size_bytes == @sizeOf(InputBindings)) {
                break :blk;
            }
        } else |_| {}
        {
            sys.bindings.init();
            const phys = inp.phys;
            sys.bindings.bind(.exit, phys(9, .press));
            sys.bindings.bindAlt(.exit, .{ .wm = .{ .event = .delete } });
            sys.bindings.bind(.c4on, phys(38, .press));
            sys.bindings.bind(.c4off, phys(38, .release));
            sys.bindings.bind(.cs4on, phys(25, .press));
            sys.bindings.bind(.cs4off, phys(25, .release));
            sys.bindings.bind(.d4on, phys(39, .press));
            sys.bindings.bind(.d4off, phys(39, .release));
            sys.bindings.bind(.ds4on, phys(26, .press));
            sys.bindings.bind(.ds4off, phys(26, .release));
            sys.bindings.bind(.e4on, phys(40, .press));
            sys.bindings.bind(.e4off, phys(40, .release));
            sys.bindings.bind(.f4on, phys(41, .press));
            sys.bindings.bind(.f4off, phys(41, .release));
            sys.bindings.bind(.fs4on, phys(28, .press));
            sys.bindings.bind(.fs4off, phys(28, .release));
            sys.bindings.bind(.g4on, phys(42, .press));
            sys.bindings.bind(.g4off, phys(42, .release));
            sys.bindings.bind(.gs4on, phys(29, .press));
            sys.bindings.bind(.gs4off, phys(29, .release));
            sys.bindings.bind(.a4on, phys(43, .press));
            sys.bindings.bind(.a4off, phys(43, .release));
            sys.bindings.bind(.as4on, phys(30, .press));
            sys.bindings.bind(.as4off, phys(30, .release));
            sys.bindings.bind(.b4on, phys(44, .press));
            sys.bindings.bind(.b4off, phys(44, .release));
            sys.bindings.bind(.c5on, phys(45, .press));
            sys.bindings.bind(.c5off, phys(45, .release));
            sys.bindings.bind(.octave_prev, phys(24, .press));
            sys.bindings.bind(.octave_next, phys(27, .press));

            try std.fs.cwd().writeFile2(.{
                .sub_path = "input.dat",
                .data = std.mem.asBytes(&sys.bindings),
                .flags = .{},
            });
        }
    }

    try Timer.init(&sys.timer_update, 60);

    try sys.ui.init();
    defer sys.ui.kill();

    try sys.gpu.init(sys.ui);
    defer sys.gpu.kill();

    try sys.sound.init(allocator);
    defer sys.sound.kill();

    sys.sound.master_volume = 0.5;

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

    var t = try std.time.Timer.start();

    loop: while (true) {
        sys.ui.eventsPoll(&input);

        try sys.timer_update.accumulate_duration();
        while (sys.timer_update.canTick()) {
            std.debug.print("--- frame {} ---\n", .{sys.timer_update.frame_index});
            defer input.frameConsume();
            defer sys.timer_update.tick();

            if (sys.bindings.check(.exit, input)) {
                break :loop;
            }

            try recorder.frame_write(sys.timer_update.frame_index, sys.bindings, input);

            while (recorder.frame_advance(sys.timer_update.frame_index)) |event| {
                std.debug.print("{any}\n", .{event});
                if (event != .action) {
                    continue;
                }
                const action = event.action;
                switch (action) {
                    .c4on => key_voices.c4 = sys.sound.synth.voice_start(261.63 * octave),
                    .c4off => sys.sound.synth.voice_end(key_voices.c4),
                    .cs4on => key_voices.cs4 = sys.sound.synth.voice_start(277.18 * octave),
                    .cs4off => sys.sound.synth.voice_end(key_voices.cs4),
                    .d4on => key_voices.d4 = sys.sound.synth.voice_start(293.66 * octave),
                    .d4off => sys.sound.synth.voice_end(key_voices.d4),
                    .ds4on => key_voices.ds4 = sys.sound.synth.voice_start(311.13 * octave),
                    .ds4off => sys.sound.synth.voice_end(key_voices.ds4),
                    .e4on => key_voices.e4 = sys.sound.synth.voice_start(329.63 * octave),
                    .e4off => sys.sound.synth.voice_end(key_voices.e4),
                    .f4on => key_voices.f4 = sys.sound.synth.voice_start(349.23 * octave),
                    .f4off => sys.sound.synth.voice_end(key_voices.f4),
                    .fs4on => key_voices.fs4 = sys.sound.synth.voice_start(369.99 * octave),
                    .fs4off => sys.sound.synth.voice_end(key_voices.fs4),
                    .g4on => key_voices.g4 = sys.sound.synth.voice_start(392.00 * octave),
                    .g4off => sys.sound.synth.voice_end(key_voices.g4),
                    .gs4on => key_voices.gs4 = sys.sound.synth.voice_start(415.30 * octave),
                    .gs4off => sys.sound.synth.voice_end(key_voices.gs4),
                    .a4on => key_voices.a4 = sys.sound.synth.voice_start(440.00 * octave),
                    .a4off => sys.sound.synth.voice_end(key_voices.a4),
                    .as4on => key_voices.as4 = sys.sound.synth.voice_start(466.16 * octave),
                    .as4off => sys.sound.synth.voice_end(key_voices.as4),
                    .b4on => key_voices.b4 = sys.sound.synth.voice_start(493.88 * octave),
                    .b4off => sys.sound.synth.voice_end(key_voices.b4),
                    .c5on => key_voices.c5 = sys.sound.synth.voice_start(523.25 * octave),
                    .c5off => sys.sound.synth.voice_end(key_voices.c5),
                    .octave_prev => octave *= 0.5,
                    .octave_next => octave *= 2,
                    else => {},
                }
            }
        }

        if ((input.wm.flags & @intFromEnum(inp.Input.Wm.Event.resize)) != 0) {
            try sys.gpu.swapchainInit(false);
        }

        try sys.gpu.frameDraw(@as(f32, @floatFromInt(t.read())) / 1e9);

        try sys.sound.update();
    }

    std.debug.print("exited cleanly\n", .{});
}
