const std = @import("std");

/// NOTE: may only contain `size - 1` items at once as implemented
pub fn CircularBuffer(comptime T: type, comptime size: usize) type {
    std.debug.assert(std.math.isPowerOfTwo(size));
    const mask = size - 1;
    return struct {
        const Self = @This();

        value: [size]T,
        head_w: usize,
        head_r: usize,

        pub fn init(self: *Self) void {
            self.* = .{
                .value = undefined,
                .head_w = 0,
                .head_r = 0,
            };
        }

        pub fn write(self: *Self, value: T) error{Full}!void {
            const next = (self.head_w + 1) & mask;
            if (next == self.head_r) {
                return error.Full;
            }
            self.value[self.head_w] = value;
            self.head_w = next;
        }

        pub fn peek(self: *Self) ?T {
            if (self.head_r == self.head_w) {
                return null;
            }
            return self.value[self.head_r];
        }

        pub fn peek_w(self: *Self) ?T {
            if (self.head_r == self.head_w) {
                return null;
            }
            return self.value[(self.head_w - 1) & mask];
        }

        pub fn rewrite(self: *Self, value: T) error{Empty}!void {
            if (self.head_r == self.head_w) {
                return error.Empty;
            }
            self.value[(self.head_w - 1) & mask] = value;
        }

        pub fn consume(self: *Self) error{Empty}!void {
            if (self.head_r == self.head_w) {
                return error.Empty;
            }
            self.head_r = (self.head_r + 1) & mask;
        }

        pub fn read(self: *Self) error{Empty}!T {
            if (self.head_r == self.head_w) {
                return error.Empty;
            }
            const value = self.value[self.head_r];
            self.head_r = (self.head_r + 1) & mask;
            return value;
        }
    };
}

test "circular buffer" {
    const TestEvent = union(enum) {
        f: f64,
        i: i32,
        s: [8]u8,
    };

    var buf: CircularBuffer(TestEvent, 4) = undefined;
    buf.init();
    try buf.write(.{ .f = 1.1 });
    try buf.write(.{ .i = 2 });
    try buf.write(.{ .f = 3.3 });
    try std.testing.expectError(error.Full, buf.write(.{ .s = "hell\x00\x00\x00\x00".* }));
    try std.testing.expectEqual(TestEvent{ .f = 1.1 }, try buf.read());
    try std.testing.expectEqual(TestEvent{ .i = 2 }, try buf.read());
    try buf.write(.{ .s = "hell\x00\x00\x00\x00".* });
    try std.testing.expectEqual(TestEvent{ .f = 3.3 }, try buf.read());
    try std.testing.expectEqual(TestEvent{ .s = "hell\x00\x00\x00\x00".* }, try buf.read());
    try std.testing.expectError(error.Empty, buf.read());
}
