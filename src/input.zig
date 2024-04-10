const std = @import("std");

pub const Binding = struct {
    const Predicate = union(enum) {
        const Physical = struct {
            event: enum(u8) {
                down,
                up,
                press,
                release,
            },
            key: enum(u8) {
                button1 = 1,
                button2 = 2,
                button3 = 3,
                button4 = 4,
                button5 = 5,
                esc = 9,
            },

            fn check(self: Physical, keys: Input.Keys) bool {
                const index = @intFromEnum(self.key);
                return switch (self.event) {
                    .down => keys.down(index),
                    .up => keys.up(index),
                    .press => keys.pressed(index),
                    .release => keys.released(index),
                };
            }
        };

        const Wm = struct {
            event: Input.Wm.Event,

            fn check(self: Wm, wm: Input.Wm) bool {
                return (wm.flags & @intFromEnum(self.event)) != 0;
            }
        };

        physical: Physical,
        wm: Wm,
        none: struct {},

        fn check(self: Predicate, input: Input) bool {
            return switch (self) {
                .physical => |e| e.check(input.keys),
                .wm => |e| e.check(input.wm),
                .none => false,
            };
        }
    };

    main: Predicate = .none,
    alt: Predicate = .none,

    pub fn check(self: @This(), input: Input) bool {
        return self.main.check(input) or self.alt.check(input);
    }
};

pub const Input = struct {
    pub const Wm = struct {
        pub const Event = enum(u8) {
            delete_window = 0b01,
        };

        flags: u8 = 0,
    };

    pub const Keys = struct {
        state: [32]u8 = [_]u8{0} ** 32,
        prev: [32]u8 = [_]u8{0} ** 32,

        pub fn set(self: *Keys, index: u8) void {
            self.state[index >> 3] |= std.math.shl(u8, 1, index & 7);
        }

        pub fn unset(self: *Keys, index: u8) void {
            self.state[index >> 3] &= ~std.math.shl(u8, 1, index & 7);
        }

        pub fn down(self: Keys, index: u8) bool {
            return (self.state[index >> 3] & std.math.shl(u8, 1, index & 7)) != 0;
        }

        pub fn up(self: Keys, index: u8) bool {
            return (self.state[index >> 3] & std.math.shl(u8, 1, index & 7)) == 0;
        }

        pub fn pressed(self: Keys, index: u8) bool {
            return (self.prev[index >> 3] & std.math.shl(u8, 1, index & 7)) == 0 and self.down(index);
        }

        pub fn released(self: Keys, index: u8) bool {
            return (self.prev[index >> 3] & std.math.shl(u8, 1, index & 7)) != 0 and self.up(index);
        }

        fn nextFrame(self: *Keys) void {
            std.mem.copyForwards(u8, &self.prev, &self.state);
        }
    };

    keys: Keys = .{},
    wm: Wm = .{},

    pub fn update(self: *Input) void {
        self.keys.nextFrame();
        self.wm.flags = 0;
    }
};
