const std = @import("std");
const synth = @import("synth.zig");
const c = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const frames_per_second = 500;

pub const Alsa = struct {
    audio_data: []u8,
    pcm_handle: ?*c.snd_pcm_t,
    samples_tot: usize,
    sample_rate: u32,
    channel_count: u32,
    frame_size: c.snd_pcm_uframes_t,
    format: i32,
    format_width: u32,
    master_volume: f64,
    synth: synth.Synth,

    pub fn init(self: *Alsa, allocator: std.mem.Allocator) !void {
        std.debug.print("\n=== ALSA ===\n", .{});

        var card_i: c_int = -1;

        // enumerate devices
        while (true) {
            try errCheck(c.snd_card_next(&card_i));

            if (card_i == -1)
                break;

            var card_sbuf = [_]u8{0} ** 16;
            const card_s = try std.fmt.bufPrint(&card_sbuf, "hw:{}", .{card_i});

            var ctl: ?*c.snd_ctl_t = null;

            try errCheck(c.snd_ctl_open(&ctl, card_s.ptr, 0));
            defer errCheck(c.snd_ctl_close(ctl)) catch {};

            {
                var ctl_card_info: ?*c.snd_ctl_card_info_t = null;
                try errCheck(c.snd_ctl_card_info_malloc(&ctl_card_info));
                defer c.snd_ctl_card_info_free(ctl_card_info);

                try errCheck(c.snd_ctl_card_info(ctl, ctl_card_info));
                const card_name = std.mem.span(c.snd_ctl_card_info_get_name(ctl_card_info));
                std.debug.print("\nSound Card Name: {s}\n", .{card_name});
            }

            var device_i: c_int = -1;
            while (true) {
                try errCheck(c.snd_ctl_pcm_next_device(ctl, &device_i));
                if (device_i == -1)
                    break;

                var device_sbuf = [_]u8{0} ** 16;
                const device_s = try std.fmt.bufPrint(&device_sbuf, "plughw:{},{}", .{ card_i, device_i });

                std.debug.print("- {s}\n", .{device_s});
            }
        }

        // TODO: let user choose device; first, we'll need to implement support for all formats
        const pcm_name = "default";

        self.sample_rate = 44100; // CD quality audio; 2*2*3*3*5*5*7*7
        self.frame_size = self.sample_rate / frames_per_second;
        var period_size: c.snd_pcm_uframes_t = 0;
        var buffer_size: u32 = 0;
        self.channel_count = 2;
        self.format = 0;
        self.format_width = 0;
        const subformat: i32 = c.SND_PCM_SUBFORMAT_STD;

        // pcm
        self.pcm_handle = null;
        try errCheck(c.snd_pcm_open(&self.pcm_handle, pcm_name, c.SND_PCM_STREAM_PLAYBACK, c.SND_PCM_NONBLOCK));

        std.debug.print("\nPCM:\n", .{});
        // TODO: double check we don't need to free any strings
        const pcm_type = c.snd_pcm_type(self.pcm_handle);
        std.debug.print("- type: {s}\n", .{c.snd_pcm_type_name(pcm_type)});
        const stream = c.snd_pcm_stream(self.pcm_handle);
        std.debug.print("- stream name: {s}\n", .{c.snd_pcm_stream_name(stream)});

        // configure hw
        {
            var hw_params: ?*c.snd_pcm_hw_params_t = null;
            try errCheck(c.snd_pcm_hw_params_malloc(&hw_params));
            defer c.snd_pcm_hw_params_free(hw_params);

            try errCheck(c.snd_pcm_hw_params_any(self.pcm_handle, hw_params));
            try errCheck(c.snd_pcm_hw_params_set_access(self.pcm_handle, hw_params, c.SND_PCM_ACCESS_RW_INTERLEAVED));

            // select format
            {
                var format_mask: ?*c.snd_pcm_format_mask_t = null;
                try errCheck(c.snd_pcm_format_mask_malloc(&format_mask));
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
                        self.format = candidate;
                        break;
                    }
                }
            }

            try errCheck(c.snd_pcm_hw_params_set_format(self.pcm_handle, hw_params, self.format));
            try errCheck(c.snd_pcm_hw_params_set_subformat(self.pcm_handle, hw_params, subformat));
            try errCheck(c.snd_pcm_hw_params_set_rate_near(self.pcm_handle, hw_params, &self.sample_rate, 0));
            try errCheck(c.snd_pcm_hw_params_set_period_size_near(self.pcm_handle, hw_params, &self.frame_size, 0));
            try errCheck(c.snd_pcm_hw_params_set_channels_near(self.pcm_handle, hw_params, &self.channel_count));

            period_size = self.frame_size * self.channel_count;
            try errCheck(c.snd_pcm_hw_params_set_buffer_size_near(self.pcm_handle, hw_params, &period_size));
            try errCheck(c.snd_pcm_hw_params(self.pcm_handle, hw_params));

            self.format_width = @intCast(c.snd_pcm_format_physical_width(self.format));
            buffer_size = @as(u32, @intCast(period_size)) * (self.format_width >> 3);

            std.debug.print("\nHardware params:\n", .{});
            std.debug.print("- sample rate: {}\n", .{self.sample_rate});
            std.debug.print("- frame size: {}B\n", .{self.frame_size});
            std.debug.print("- period size: {}B\n", .{period_size});
            std.debug.print("- buffer size: {}B\n", .{buffer_size});
            std.debug.print("- channel count: {}\n", .{self.channel_count});

            std.debug.print("- access: {s}\n", .{c.snd_pcm_access_name(c.SND_PCM_ACCESS_RW_INTERLEAVED)});
            std.debug.print("- format: {s} ({s})\n", .{ c.snd_pcm_format_name(self.format), c.snd_pcm_format_description(self.format) });
            std.debug.print("- subformat: {s} ({s})\n", .{ c.snd_pcm_subformat_name(subformat), c.snd_pcm_subformat_description(subformat) });
        }

        self.audio_data = try allocator.alignedAlloc(u8, 8, buffer_size);

        // TODO: does not seem to work, needs more investigation
        // avoid initial "click"
        try errCheck(c.snd_pcm_format_set_silence(self.format, self.audio_data.ptr, @truncate(self.frame_size)));

        self.samples_tot = 0;
        self.master_volume = 1.0;
        self.synth = synth.Synth{};
    }

    pub fn kill(self: *Alsa) void {
        errCheck(c.snd_pcm_close(self.pcm_handle)) catch {};
    }

    pub fn update(self: *Alsa) !void {
        const time_delta = 1.0 / @as(f64, @floatFromInt(self.sample_rate));

        while (true) {
            const avail = c.snd_pcm_avail_update(self.pcm_handle);
            if (avail == -c.EPIPE) {
                // NOTE: XRun means buffer underrun or overrun
                // return error.AlsaXRun;
            } else try errCheck(@truncate(avail));

            const samples_written = c.snd_pcm_writei(
                self.pcm_handle,
                self.audio_data.ptr,
                self.frame_size,
            );
            if (samples_written == -c.EAGAIN) {
                // NOTE: The PCM device is not ready for more data, skip this cycle.
                return;
            }

            if (samples_written < 0) {
                try errCheck(c.snd_pcm_recover(self.pcm_handle, @truncate(samples_written), 0));
            } else {
                std.debug.assert(samples_written == self.frame_size);

                self.samples_tot += @intCast(samples_written);

                // interleaved write
                for (0..self.frame_size) |sample_local| {
                    const channel_gain = 0.5;
                    const amplitude = self.master_volume * self.synth.sample(time_delta);

                    const sample = std.math.clamp(
                        channel_gain * amplitude,
                        -1,
                        1,
                    );

                    for (0..self.channel_count) |channel_index| {
                        const i = sample_local * self.channel_count + channel_index;

                        switch (self.format) {
                            c.SND_PCM_FORMAT_FLOAT64_LE => {
                                std.mem.bytesAsSlice(f64, self.audio_data)[i] = sample;
                            },
                            c.SND_PCM_FORMAT_FLOAT_LE => {
                                std.mem.bytesAsSlice(f32, self.audio_data)[i] =
                                    @floatCast(sample);
                            },
                            c.SND_PCM_FORMAT_S32_LE => {
                                const range: f64 = comptime @floatFromInt(1 << 31);
                                std.mem.bytesAsSlice(i32, self.audio_data)[i] =
                                    @intFromFloat(range * sample);
                            },
                            c.SND_PCM_FORMAT_S16_LE => {
                                const range: f64 = comptime @floatFromInt(1 << 15);
                                std.mem.bytesAsSlice(i16, self.audio_data)[i] =
                                    @intFromFloat(range * sample);
                            },
                            c.SND_PCM_FORMAT_S8 => {
                                const range: f64 = comptime @floatFromInt(1 << 7);
                                std.mem.bytesAsSlice(i8, self.audio_data)[i] =
                                    @intFromFloat(range * sample);
                            },
                            c.SND_PCM_FORMAT_U32_LE => {
                                const range: f64 = comptime @floatFromInt(1 << 31);
                                std.mem.bytesAsSlice(u32, self.audio_data)[i] =
                                    @intFromFloat((range - 1.0) * sample + range);
                            },
                            c.SND_PCM_FORMAT_U16_LE => {
                                const range: f64 = comptime @floatFromInt(1 << 15);
                                std.mem.bytesAsSlice(u16, self.audio_data)[i] =
                                    @intFromFloat((range - 1.0) * sample + range);
                            },
                            c.SND_PCM_FORMAT_U8 => {
                                const range: f64 = comptime @floatFromInt(1 << 7);
                                self.audio_data[i] = @intFromFloat((range - 1.0) *
                                    sample + range);
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

fn errCheck(result: c_int) !void {
    if (result < 0) {
        const msg = std.mem.span(c.snd_strerror(result));
        std.debug.print("ALSA Error: {s}\n", .{msg});
        return error.AlsaError;
    }
}
