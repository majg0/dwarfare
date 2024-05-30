const std = @import("std");

pub fn Transition(comptime State: type, comptime Event: type) type {
    return struct {
        event: Event,
        from: State,
        to: State,
    };
}

pub fn Fsm(
    comptime State: type,
    comptime Event: type,
    comptime _: []const Transition(State, Event),
    comptime state_initial: State,
    comptime _: State,
) type {
    // TODO: bitfield transition matrix
    return struct {
        const Self = @This();

        state_current: State,

        fn init() Self {
            return Self{
                .state_current = state_initial,
            };
        }
    };
}

test "fsm" {
    const t = std.testing;

    const State = enum {
        init,
        menu_main,
        menu_options,
        exit,
    };

    const Event = enum {
        load,
        exit,
    };

    const transitions = [_]Transition(State, Event){
        .{ .event = .toggle, .from = .on, .to = .off },
        .{ .event = .toggle, .from = .off, .to = .on },
    };

    const fsm = Fsm(State, Event, &transitions, .off, .on).init();

    try t.expectEqual(.off, fsm.state_current);
}
