const std = @import("std");
const assert = std.debug.assert;

pub fn utf8_to_ut16(utf8: []const u8, utf16: []u16) usize {
    var utf16_index: usize = 0;

    var utf8_index: usize = 0;
    while (utf8_index != utf8.len) : ({
        utf8_index += 1;
    }) {
        const byte1 = utf8[utf8_index];

        if ((byte1 & 0b1000_0000) == 0b0000_0000) {
            // (0)xxx_xxxx (7 bits)
            assert(utf16.len >= utf16_index + 1);
            utf16[utf16_index] = byte1 & 0b0111_1111;
            utf16_index += 1;
        } else if ((byte1 & 0b0110_0000) == 0b0100_0000) {
            // 1(10)x_xxxx (5 bits) + 00xx_xxxx (6 bits)
            const byte2 = utf8[utf8_index + 1];
            utf8_index += 1;

            assert(utf16.len >= utf16_index + 1);
            utf16[utf16_index] = (@as(u16, byte1 & 0b0001_1111) << 6) | (byte2 & 0b0011_1111);
            utf16_index += 1;
        } else if ((byte1 & 0b0111_0000) == 0b0110_0000) {
            // 1(110)_xxxx (4 bits) + 00xx_xxxx (6 bits) + 00xx_xxxx (6 bits)
            const byte2 = utf8[utf8_index + 1];
            const byte3 = utf8[utf8_index + 2];
            utf8_index += 2;

            assert(utf16.len >= utf16_index + 1);
            utf16[utf16_index] = (@as(u16, byte1 & 0b0000_1111) << 12) | (@as(u16, byte2 & 0b0011_1111) << 6) | (byte3 & 0b0011_1111);
            utf16_index += 1;
        } else if ((byte1 & 0b0111_1000) == 0b0111_0000) {
            // 1(111_0)xxx (3 bits) + 00xx_xxxx (6 bits) + 00xx_xxxx (6 bits) + 00xx_xxxx (6 bits)
            const byte2 = utf8[utf8_index + 1];
            const byte3 = utf8[utf8_index + 2];
            const byte4 = utf8[utf8_index + 3];
            utf8_index += 3;

            const cp: u32 = (@as(u32, byte1 & 0b0000_0111) << 18) |
                (@as(u32, byte2 & 0b0011_1111) << 12) |
                (@as(u32, byte3 & 0b0011_1111) << 6) |
                @as(u32, byte4 & 0b0011_1111);
            const cptemp = cp - 0b1_0000_0000_0000_0000;
            const high_surrogate = 0b1101_1000_0000_0000 + ((cptemp >> 10) & 0b11_1111_1111);
            const low_surrogate = 0b1101_1100_0000_0000 + (cptemp & 0b11_1111_1111);
            assert(utf16.len >= utf16_index + 2);
            utf16[utf16_index + 0] = @truncate(high_surrogate);
            utf16[utf16_index + 1] = @truncate(low_surrogate);
            utf16_index += 2;
        } else {
            unreachable;
        }
    }

    return utf16_index;
}
