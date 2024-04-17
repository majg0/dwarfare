const std = @import("std");

pub const Synth = struct {
    const Interpolation = enum {
        linear,
    };

    const Timbre = struct {
        frequencies: [timbre_depth]f64 = undefined,
        velocities: [timbre_depth]f64 = undefined,

        fn standard_normalized(velocities: [timbre_depth]f64) Timbre {
            var result = Timbre{
                .frequencies = .{ 1, 2, 3, 4, 5, 6, 7, 8 },
                .velocities = velocities,
            };
            var sum: f64 = 0;
            for (velocities) |velocity| {
                sum += velocity;
            }
            const factor = 1 / sum;
            for (&result.velocities) |*velocity| {
                velocity.* *= factor;
            }
            return result;
        }
    };

    const Adsr = struct {
        const Stage = struct {
            /// Speed rather than duration easily allows infinite length.
            /// A stage ends when its accumulated duration >= 1.
            /// The easy way to write speeds are to prepend `1.0 / ` and pretend they're durations.
            /// For example, a `1.0 / 0.1` speed will give rise to a `0.1` second duration.
            speed: f64 = 0,
            value_target: f64 = 0,
            interpolation: Interpolation,
        };

        const Envelope = struct {
            const stage_count_max = 5;
            const stage_last = stage_count_max - 1;
            stage: [stage_count_max]Stage,
        };

        const envelope_default = Envelope{
            .stage = .{
                .{ .speed = 0, .value_target = 0, .interpolation = .linear },
                .{ .speed = 1.0 / 0.05, .value_target = 1, .interpolation = .linear },
                .{ .speed = 1.0 / 0.05, .value_target = 0.5, .interpolation = .linear },
                .{ .speed = 0, .value_target = 0, .interpolation = .linear },
                .{ .speed = 1.0 / 2.0, .value_target = 0, .interpolation = .linear },
            },
        };

        const State = struct {
            stage: usize = 0,
            phase: f64 = 0,
            /// avoids discontinuities by remembering state
            value: f64 = 0,
            /// necessary to know how to interpolate; set to `value` on every transition
            value_start: f64 = 0,

            fn transition(self: *State, stage: usize) void {
                self.phase = 0;
                self.stage = stage;
                self.value_start = self.value;
            }

            fn sample(self: *State, time_delta: f64) f64 {
                const stage = Synth.Adsr.envelope_default.stage[self.stage];
                self.phase += stage.speed * time_delta;
                if (self.phase >= 1) {
                    if (self.stage == Synth.Adsr.Envelope.stage_last) {
                        self.value = 0;
                        self.transition(0);
                    } else {
                        self.value = stage.value_target;
                        self.transition(self.stage + 1);
                    }
                } else {
                    const t = self.phase;
                    self.value = switch (stage.interpolation) {
                        .linear => self.value_start * (1 - t) + stage.value_target * t,
                    };
                }
                return self.value;
            }
        };
    };

    const timbre_depth = 8;
    const timbre = [_]Timbre{
        Timbre.standard_normalized(.{ 1, 0, 0, 0, 0, 0, 0, 0 }),
        Timbre.standard_normalized(blk: {
            var velocities: [timbre_depth]f64 = undefined;
            for (&velocities, 0..) |*velocity, index| {
                velocity.* = 1.0 / @as(f64, @floatFromInt(1 << index));
            }
            break :blk velocities;
        }),
        Timbre.standard_normalized(.{ 1, 0.75, 0.65, 0.55, 0.5, 0.45, 0.4, 0.35 }),
    };
    const timbre_index_sine = 0;
    const timbre_index_harmonic = 1;
    const timbre_index_violin = 2;

    const Voice = struct {
        /// avoids stolen voices ending too early when `voice_end` is called with a stale generation
        generation: u32 = 0,
        phases: [timbre_depth]f64 = blk: {
            var phases: [timbre_depth]f64 = undefined;
            for (&phases, 0..) |*phase, index| {
                // NOTE: opt out of what's known as "auditory fusion"
                phase.* = @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(voice_count));
            }
            break :blk phases;
        },
        frequency: f64 = 0,
        timbre_index: usize = Synth.timbre_index_violin,
        state: Adsr.State = .{},
    };

    const voice_count_bits = 4;
    const voice_count = 1 << voice_count_bits;
    const voice_count_mask = voice_count - 1;

    voice: [voice_count]Voice = blk: {
        var voices: [voice_count]Voice = undefined;
        for (&voices) |*voice| {
            voice.* = .{};
        }
        break :blk voices;
    },
    voice_index_next: usize = 0,

    fn voice_alloc(self: *Synth) usize {
        const voice_index_start = self.voice_index_next;
        self.voice_index_next = (self.voice_index_next + 1) & voice_count_mask;

        for (0..voice_count_mask) |offset| {
            const voice_index = (voice_index_start + offset) & voice_count_mask;
            if (self.voice[voice_index].state.stage == 0) {
                return voice_index;
            }
        }

        for (0..voice_count_mask) |offset| {
            const voice_index = (voice_index_start + offset) & voice_count_mask;
            if (self.voice[voice_index].state.stage == Adsr.Envelope.stage_last) {
                return voice_index;
            }
        }

        return self.voice_index_next;
    }

    pub fn voice_start(self: *Synth, frequency: f64) usize {
        const index = self.voice_alloc();
        var v = &self.voice[index];
        v.frequency = frequency;
        v.state.transition(1);
        v.generation += 1;
        return (v.generation << 16) + index;
    }

    pub fn voice_end(self: *Synth, id: usize) void {
        const index = id & 0xffff;
        const generation = (id & 0xffff0000) >> 16;
        if (self.voice[index].generation == generation) {
            self.voice[index].state.transition(Adsr.Envelope.stage_last);
        }
    }

    pub fn sample(self: *Synth, time_delta: f64) f64 {
        var amplitude: f64 = 0;
        for (&self.voice) |*voice| {
            for (&voice.phases, 0..) |*phase, phase_index| {
                const t = timbre[voice.timbre_index];
                amplitude += wavetable_square.read(phase.*) *
                    t.velocities[phase_index] *
                    voice.state.sample(time_delta);
                phase.* = std.math.modf(phase.* +
                    voice.frequency *
                    t.frequencies[phase_index] *
                    time_delta).fpart;
            }
        }
        return amplitude;
    }
};

fn Wavetable(comptime sample_count_power_of_2: comptime_int) type {
    return struct {
        const sample_count = 1 << sample_count_power_of_2;
        const sample_mask = sample_count - 1;

        sample: [sample_count]f64 = undefined,

        pub fn read(self: @This(), phase: f64) f64 {
            const offset: usize = @intFromFloat(phase * sample_count);
            return self.sample[offset & sample_mask];
        }
    };
}

pub const wavetable_square = blk: {
    var wavetable = Wavetable(1){};
    wavetable.sample[0] = 1;
    wavetable.sample[1] = -1;
    break :blk wavetable;
};
pub const wavetable_sine = blk: {
    var wavetable = Wavetable(9){};
    const N = @TypeOf(wavetable).sample_count;
    const step: f64 = @floatFromInt(N);
    for (0..N) |index| {
        const phase: f64 = @as(f64, @floatFromInt(index)) / step;
        wavetable.sample[index] = @sin(std.math.tau * phase);
    }
    break :blk wavetable;
};
