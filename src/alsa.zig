const std = @import("std");
const c = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const AlsaAudio = struct {
    audio_data: []u8,
    pcm_handle: ?*c.snd_pcm_t,
    samples_tot: usize,
    sample_rate: u32,
    channel_count: u32,
    frame_size: c.snd_pcm_uframes_t,
    arena: std.heap.ArenaAllocator,
    format: i32,
    format_width: u32,
    master_volume: f64,

    pub fn kill(self: *AlsaAudio) void {
        self.arena.deinit();
        err_check(c.snd_pcm_close(self.pcm_handle)) catch {};
    }
    pub fn update(self: *AlsaAudio) !void {
        while (true) {
            const avail = c.snd_pcm_avail_update(self.pcm_handle);
            if (avail == -c.EPIPE) {
                // NOTE: XRun means buffer underrun or overrun
                return error.AlsaXRun;
            } else try err_check(@truncate(avail));

            const samples_written = c.snd_pcm_writei(self.pcm_handle, self.audio_data.ptr, self.frame_size);
            if (samples_written == -c.EAGAIN) {
                // The PCM device is not ready for more data, skip this cycle.
                // TODO: we could yield null here to break a loop
                return;
            }

            if (samples_written < 0) {
                try err_check(c.snd_pcm_recover(self.pcm_handle, @truncate(samples_written), 0));
            } else {
                std.debug.assert(samples_written == self.frame_size);

                // TODO: we could yield to consumer here for handling the frame
                self.samples_tot += @intCast(samples_written);

                // interleaved write
                for (0..self.frame_size) |sample_local| {
                    const sample_global = self.samples_tot + sample_local;
                    const step = 1.0 / @as(f64, @floatFromInt(self.sample_rate));
                    const phase_root = @as(f64, @floatFromInt(sample_global % self.sample_rate)) * step;

                    const vol = 0.5 * self.master_volume;
                    const amp = wavetable_read(wavetable_sine, 440 * phase_root);
                    for (0..self.channel_count) |channel_index| {
                        const i = sample_local * self.channel_count + channel_index;

                        switch (self.format) {
                            c.SND_PCM_FORMAT_FLOAT64_LE => {
                                std.mem.bytesAsSlice(f64, self.audio_data)[i] = vol * amp;
                            },
                            c.SND_PCM_FORMAT_FLOAT_LE => {
                                std.mem.bytesAsSlice(f32, self.audio_data)[i] = @floatCast(vol * amp);
                            },
                            c.SND_PCM_FORMAT_S32_LE => {
                                const range: f64 = comptime @floatFromInt(1 << 31);
                                std.mem.bytesAsSlice(i32, self.audio_data)[i] = @intFromFloat(range * vol * amp);
                            },
                            c.SND_PCM_FORMAT_S16_LE => {
                                const range: f64 = comptime @floatFromInt(1 << 15);
                                std.mem.bytesAsSlice(i16, self.audio_data)[i] = @intFromFloat(range * vol * amp);
                            },
                            c.SND_PCM_FORMAT_S8 => {
                                const range: f64 = comptime @floatFromInt(1 << 7);
                                std.mem.bytesAsSlice(i8, self.audio_data)[i] = @intFromFloat(range * vol * amp);
                            },
                            c.SND_PCM_FORMAT_U32_LE => {
                                const range: f64 = comptime @floatFromInt(1 << 31);
                                std.mem.bytesAsSlice(u32, self.audio_data)[i] = @intFromFloat((range - 1.0) * (vol * amp) + range);
                            },
                            c.SND_PCM_FORMAT_U16_LE => {
                                const range: f64 = comptime @floatFromInt(1 << 15);
                                std.mem.bytesAsSlice(u16, self.audio_data)[i] = @intFromFloat((range - 1.0) * (vol * amp) + range);
                            },
                            c.SND_PCM_FORMAT_U8 => {
                                const range: f64 = comptime @floatFromInt(1 << 7);
                                self.audio_data[i] = @intFromFloat((range - 1.0) * (vol * amp) + range);
                            },
                            else => {
                                std.debug.print("missing format implementation {}", .{self.format});
                                return error.AlsaUnsupportedFormat;
                            },
                        }
                    }
                }
            }
        }
    }
};

fn err_check(result: c_int) !void {
    if (result < 0) {
        const msg = std.mem.span(c.snd_strerror(result));
        std.debug.print("ALSA Error: {s}\n", .{msg});
        return error.AlsaError;
    }
}

pub fn init() !AlsaAudio {
    std.debug.print("\n=== ALSA ===\n", .{});

    // TODO: move this out to a global pre-alloc
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    var card_i: c_int = -1;

    // enumerate devices
    while (true) {
        try err_check(c.snd_card_next(&card_i));

        if (card_i == -1)
            break;

        var card_sbuf = [_]u8{0} ** 16;
        const card_s = try std.fmt.bufPrint(&card_sbuf, "hw:{}", .{card_i});

        var ctl: ?*c.snd_ctl_t = null;

        try err_check(c.snd_ctl_open(&ctl, card_s.ptr, 0));
        defer err_check(c.snd_ctl_close(ctl)) catch {};

        {
            var ctl_card_info: ?*c.snd_ctl_card_info_t = null;
            try err_check(c.snd_ctl_card_info_malloc(&ctl_card_info));
            defer c.snd_ctl_card_info_free(ctl_card_info);

            try err_check(c.snd_ctl_card_info(ctl, ctl_card_info));
            const card_name = std.mem.span(c.snd_ctl_card_info_get_name(ctl_card_info));
            std.debug.print("\nSound Card Name: {s}\n", .{card_name});
        }

        var device_i: c_int = -1;
        while (true) {
            try err_check(c.snd_ctl_pcm_next_device(ctl, &device_i));
            if (device_i == -1)
                break;

            var device_sbuf = [_]u8{0} ** 16;
            const device_s = try std.fmt.bufPrint(&device_sbuf, "plughw:{},{}", .{ card_i, device_i });

            std.debug.print("- {s}\n", .{device_s});
        }
    }

    // TODO: let user choose device; first, we'll need to implement support for all formats
    const pcm_name = "default";

    var sample_rate: u32 = 44100; // CD quality audio; 2*2*3*3*5*5*7*7
    const frames_per_second = 525; // = 3*5*5*7
    var frame_size: c.snd_pcm_uframes_t = sample_rate / frames_per_second;
    var period_size: c.snd_pcm_uframes_t = 0;
    var buffer_size: u32 = 0;
    var channel_count: u32 = 2;
    var format: i32 = 0;
    var format_width: u32 = 0;
    const subformat: i32 = c.SND_PCM_SUBFORMAT_STD;

    // pcm
    var pcm_handle: ?*c.snd_pcm_t = null;
    try err_check(c.snd_pcm_open(&pcm_handle, pcm_name, c.SND_PCM_STREAM_PLAYBACK, c.SND_PCM_NONBLOCK));

    std.debug.print("\nPCM:\n", .{});
    // TODO: double check we don't need to free any strings
    const pcm_type = c.snd_pcm_type(pcm_handle);
    std.debug.print("- type: {s}\n", .{c.snd_pcm_type_name(pcm_type)});
    const stream = c.snd_pcm_stream(pcm_handle);
    std.debug.print("- stream name: {s}\n", .{c.snd_pcm_stream_name(stream)});

    // configure hw
    {
        var hw_params: ?*c.snd_pcm_hw_params_t = null;
        try err_check(c.snd_pcm_hw_params_malloc(&hw_params));
        defer c.snd_pcm_hw_params_free(hw_params);

        try err_check(c.snd_pcm_hw_params_any(pcm_handle, hw_params));
        try err_check(c.snd_pcm_hw_params_set_access(pcm_handle, hw_params, c.SND_PCM_ACCESS_RW_INTERLEAVED));

        // select format
        {
            var format_mask: ?*c.snd_pcm_format_mask_t = null;
            try err_check(c.snd_pcm_format_mask_malloc(&format_mask));
            defer c.snd_pcm_format_mask_free(format_mask);
            c.snd_pcm_hw_params_get_format_mask(hw_params, format_mask);

            const format_priorities = [_]u16{
                c.SND_PCM_FORMAT_FLOAT64_LE,
                c.SND_PCM_FORMAT_FLOAT_LE,
                c.SND_PCM_FORMAT_S32_LE,
                c.SND_PCM_FORMAT_S16_LE,
                c.SND_PCM_FORMAT_S8,
                c.SND_PCM_FORMAT_U32_LE,
                c.SND_PCM_FORMAT_U16_LE,
                c.SND_PCM_FORMAT_U8,
            };

            for (format_priorities) |candidate| {
                if (c.snd_pcm_format_mask_test(format_mask, candidate) == std.math.shl(u32, 1, candidate)) {
                    format = candidate;
                    break;
                }
            }
        }

        try err_check(c.snd_pcm_hw_params_set_format(pcm_handle, hw_params, format));
        try err_check(c.snd_pcm_hw_params_set_subformat(pcm_handle, hw_params, subformat));
        try err_check(c.snd_pcm_hw_params_set_rate_near(pcm_handle, hw_params, &sample_rate, 0));
        try err_check(c.snd_pcm_hw_params_set_period_size_near(pcm_handle, hw_params, &frame_size, 0));
        try err_check(c.snd_pcm_hw_params_set_channels_near(pcm_handle, hw_params, &channel_count));

        period_size = frame_size * channel_count;
        try err_check(c.snd_pcm_hw_params_set_buffer_size_near(pcm_handle, hw_params, &period_size));
        try err_check(c.snd_pcm_hw_params(pcm_handle, hw_params));

        format_width = @intCast(c.snd_pcm_format_physical_width(format));
        buffer_size = @as(u32, @intCast(period_size)) * (format_width >> 3);

        std.debug.print("\nHardware params:\n", .{});
        std.debug.print("- sample rate: {}\n", .{sample_rate});
        std.debug.print("- frame size: {}B\n", .{frame_size});
        std.debug.print("- period size: {}B\n", .{period_size});
        std.debug.print("- buffer size: {}B\n", .{buffer_size});
        std.debug.print("- channel count: {}\n", .{channel_count});

        std.debug.print("- access: {s}\n", .{c.snd_pcm_access_name(c.SND_PCM_ACCESS_RW_INTERLEAVED)});
        std.debug.print("- format: {s} ({s})\n", .{ c.snd_pcm_format_name(format), c.snd_pcm_format_description(format) });
        std.debug.print("- subformat: {s} ({s})\n", .{ c.snd_pcm_subformat_name(subformat), c.snd_pcm_subformat_description(subformat) });
    }

    const audio_data = try allocator.alignedAlloc(u8, 8, buffer_size);

    // TODO: does not seem to work, needs more investigation
    // avoid initial "click"
    try err_check(c.snd_pcm_format_set_silence(format, audio_data.ptr, @truncate(frame_size)));

    for (&wavetable_sine, 0..wavetable_len) |*sample, index| {
        const phase: f64 = @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(wavetable_len));
        sample.* = @sin(std.math.tau * phase);
    }

    return AlsaAudio{
        .audio_data = audio_data,
        .pcm_handle = pcm_handle,
        .samples_tot = 0,
        .sample_rate = sample_rate,
        .channel_count = channel_count,
        .frame_size = frame_size,
        .arena = arena,
        .format = format,
        .format_width = format_width,
        .master_volume = 1.0,
    };
}

const wavetable_len = 44100;
var wavetable_sine: [wavetable_len]f64 = undefined;
fn wavetable_read(wavetable: [wavetable_len]f64, phase: f64) f64 {
    return wavetable[@as(usize, @intFromFloat(phase * wavetable_len)) % wavetable_len];
}
