const std = @import("std");
const c = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const AlsaAudio = struct {
    pub fn kill(_: AlsaAudio) void {}
};

pub fn init() !AlsaAudio {
    var card_i: c_int = -1;
    while (true) {
        _ = c.snd_card_next(&card_i);

        if (card_i == -1)
            break;

        var card_sbuf = [_]u8{0} ** 16;
        const card_s = try std.fmt.bufPrint(&card_sbuf, "hw:{}", .{card_i});

        var ctl: ?*c.snd_ctl_t = null;
        if (c.snd_ctl_open(&ctl, card_s.ptr, 0) < 0) {
            return error.AlsaCtlOpen;
        }
        defer _ = c.snd_ctl_close(ctl);

        {
            var ctl_card_info: ?*c.snd_ctl_card_info_t = null;
            _ = c.snd_ctl_card_info_malloc(&ctl_card_info);
            defer c.snd_ctl_card_info_free(ctl_card_info);

            if (c.snd_ctl_card_info(ctl, ctl_card_info) < 0) {
                return error.AlsaCtlCardInfo;
            }
            const card_name = std.mem.span(c.snd_ctl_card_info_get_name(ctl_card_info));
            std.debug.print("Sound Card Name: {s}\n", .{card_name});
        }

        var device_i: c_int = -1;
        while (true) {
            if (0 != c.snd_ctl_pcm_next_device(ctl, &device_i) or device_i == -1)
                break;

            var device_id = [_]u8{0} ** 16;
            const device_id_slice = try std.fmt.bufPrint(&device_id, "plughw:{},{}", .{ card_i, device_i });

            std.debug.print("- {s}\n", .{device_id_slice});
        }
    }
    return AlsaAudio{};
}
