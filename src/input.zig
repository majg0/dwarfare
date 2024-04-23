const std = @import("std");

pub fn InputBindings(comptime ActionEnum: type) type {
    return struct {
        const Self = @This();
        const count: usize = @intFromEnum(ActionEnum.max_invalid);

        actions: [count]Binding(ActionEnum),

        pub fn init(self: *Self) void {
            for (&self.actions, 0..) |*binding, index| {
                binding.* = Binding(ActionEnum).init(@enumFromInt(index), .none, .none);
            }
        }

        pub fn check(self: *Self, action: ActionEnum, input: Input) bool {
            return self.actions[@intFromEnum(action)].check(input);
        }

        pub fn bind(self: *Self, action: ActionEnum, predicate: Predicate) void {
            self.actions[@intFromEnum(action)].main = predicate;
        }

        pub fn bindAlt(self: *Self, action: ActionEnum, predicate: Predicate) void {
            self.actions[@intFromEnum(action)].alt = predicate;
        }
    };
}

pub const KeyEvent = enum(u8) { down, up, press, release };

pub const Predicate = union(enum) {
    pub const Physical = struct {
        event: KeyEvent,
        key: u8,

        fn check(self: Physical, keys: Input.Keys) bool {
            const index = self.key;
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

pub fn phys(id: u8, event: KeyEvent) Predicate {
    return .{ .physical = .{ .event = event, .key = id } };
}

pub fn Binding(comptime Action: type) type {
    return struct {
        const Self = @This();

        action: Action,
        main: Predicate,
        alt: Predicate,

        pub fn init(action: Action, main: Predicate, alt: Predicate) Self {
            return Self{
                .action = action,
                .main = main,
                .alt = alt,
            };
        }

        pub fn check(self: Self, input: Input) bool {
            return self.main.check(input) or self.alt.check(input);
        }
    };
}

pub const Input = struct {
    pub const Wm = struct {
        pub const Event = enum(u8) {
            delete = 0b01,
            resize = 0b10,
        };

        flags: u8 = 0,

        fn frameConsume(self: *Wm) void {
            self.flags = 0;
        }
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

        fn frameConsume(self: *Keys) void {
            std.mem.copyForwards(u8, &self.prev, &self.state);
        }
    };

    keys: Keys = .{},
    wm: Wm = .{},

    pub fn frameConsume(self: *Input) void {
        self.keys.frameConsume();
        self.wm.frameConsume();
    }
};
