const std = @import("std");
const c = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const ALSAAudio = struct {
    audio_data: []i16,
    pcm_handle: ?*c.snd_pcm_t,
    samples_tot: usize,
    sample_rate: u32,
    channel_count: u32,
    frame_size: c.snd_pcm_uframes_t,
    arena: std.heap.ArenaAllocator,

    pub fn kill(self: *ALSAAudio) void {
        self.arena.deinit();
        errCheck(c.snd_pcm_close(self.pcm_handle)) catch {};
    }
    pub fn update(self: *ALSAAudio) !void {
        while (true) {
            const avail = c.snd_pcm_avail_update(self.pcm_handle);
            if (avail == -c.EPIPE) {
                // NOTE: XRun means buffer underrun or overrun
                return error.ALSAXRun;
            } else try errCheck(@truncate(avail));

            const samples_written = c.snd_pcm_writei(self.pcm_handle, self.audio_data.ptr, self.audio_data.len);
            if (samples_written == -c.EAGAIN) {
                // The PCM device is not ready for more data, skip this cycle.
                // TODO: we could yield null here to break a loop
                return;
            }

            if (samples_written < 0) {
                try errCheck(c.snd_pcm_recover(self.pcm_handle, @truncate(samples_written), 0));
            } else {
                // TODO: we could yield to consumer here for handling the frame
                self.samples_tot += @intCast(samples_written);

                // interleaved write
                for (0..self.frame_size) |sample_index| {
                    const phase_root = @as(f64, @floatFromInt((self.samples_tot + sample_index) % self.sample_rate)) / @as(f64, @floatFromInt(self.sample_rate));

                    // TODO: make usable later; for now this is a quick way to disable sound
                    const vol = 0;
                    const amp = wavetable_read(wavetable_sine, 440 * phase_root);
                    for (0..self.channel_count) |channel_index| {
                        const i = sample_index * self.channel_count + channel_index;
                        self.audio_data[i] = @intFromFloat(vol * amp);
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
        return error.ALSAError;
    }
}

pub fn init() !ALSAAudio {
    std.debug.print("\n=== ALSA ===\n", .{});

    // TODO: move this out to a global pre-alloc
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

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
            std.debug.print("Sound Card Name: {s}\n", .{card_name});
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
    const pcm_name = "hw:0";

    var sample_rate: u32 = 44100; // CD quality audio; 2*2*3*3*5*5*7*7
    const batches_per_second = 900; // = 2*2*3*3*5*5
    var frame_size: c.snd_pcm_uframes_t = 44100 / batches_per_second;
    var buffer_sizex: c.snd_pcm_uframes_t = 44100 / batches_per_second;
    var channel_count: u32 = 1;

    // open/close
    var pcm_handle: ?*c.snd_pcm_t = null;
    try errCheck(c.snd_pcm_open(&pcm_handle, pcm_name, c.SND_PCM_STREAM_PLAYBACK, c.SND_PCM_NONBLOCK));

    // configure hw
    {
        var hw_params: ?*c.snd_pcm_hw_params_t = null;
        try errCheck(c.snd_pcm_hw_params_malloc(&hw_params));
        defer c.snd_pcm_hw_params_free(hw_params);

        try errCheck(c.snd_pcm_hw_params_any(pcm_handle, hw_params));
        try errCheck(c.snd_pcm_hw_params_set_access(pcm_handle, hw_params, c.SND_PCM_ACCESS_RW_INTERLEAVED));
        // try errCheck(c.snd_pcm_hw_params_set_format(pcm_handle, hw_params, c.SND_PCM_FORMAT_S16_LE));
        try errCheck(c.snd_pcm_hw_params_set_rate_near(pcm_handle, hw_params, &sample_rate, 0));
        try errCheck(c.snd_pcm_hw_params_set_period_size_near(pcm_handle, hw_params, &frame_size, 0));
        try errCheck(c.snd_pcm_hw_params_set_channels_near(pcm_handle, hw_params, &channel_count));
        try errCheck(c.snd_pcm_hw_params_set_buffer_size_near(pcm_handle, hw_params, &buffer_sizex));

        std.debug.print("Sample rate {}\n", .{sample_rate});
        std.debug.print("Frame size: {}\n", .{frame_size});
        std.debug.print("Buffer size: {}\n", .{buffer_sizex});
        std.debug.print("Channel count: {}\n", .{channel_count});
        std.debug.print("Batches per second: {}\n", .{sample_rate / frame_size});
        try errCheck(c.snd_pcm_hw_params(pcm_handle, hw_params));

        var format: i32 = 0;
        try errCheck(c.snd_pcm_hw_params_get_format(hw_params, &format));
        std.debug.print("Sample format: {}\n", .{format});
        std.debug.assert(format == c.SND_PCM_FORMAT_S16_LE);
    }

    const audio_data = try allocator.alloc(i16, buffer_sizex);

    // Example: Fill the buffer with silence (you'll replace this with actual audio data)
    for (audio_data) |*sample| {
        sample.* = 0;
    }

    for (&wavetable_sine, 0..wavetable_len) |*sample, index| {
        const phase: f64 = @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(wavetable_len));
        sample.* = @sin(std.math.tau * phase);
    }

    return ALSAAudio{
        .audio_data = audio_data,
        .pcm_handle = pcm_handle,
        .samples_tot = 0,
        .sample_rate = sample_rate,
        .channel_count = channel_count,
        .frame_size = frame_size,
        .arena = arena,
    };
}

const wavetable_len = 44100;
var wavetable_sine: [wavetable_len]f64 = undefined;
fn wavetable_read(wavetable: [wavetable_len]f64, phase: f64) f64 {
    return wavetable[@as(usize, @intFromFloat(phase * wavetable_len)) % wavetable_len];
}
