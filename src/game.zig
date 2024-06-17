const std = @import("std");
const platform = @import("./platform/core/common.zig");

const GameState = struct {
    reload_count: usize,
    tick_current: usize,
    should_kill: bool,

    fn init(self: *GameState) void {
        self.reload_count = 0;
        self.tick_current = 0;
        std.debug.print("Hello from game\n", .{});
    }

    fn reload(self: *GameState) void {
        self.reload_count += 1;
        std.debug.print("Reload {}\n", .{self.reload_count});
    }

    fn receiveEvent(self: *GameState, event: *const platform.Event) void {
        switch (event.tag) {
            .key_up => {
                if (event.data.key_up.key_code == .escape) {
                    self.should_kill = true;
                }
            },
            else => {},
        }
    }

    fn update(self: *GameState) platform.UpdateResult {
        if (self.should_kill == true) {
            return platform.UpdateResult.stop_running;
        }
        return platform.UpdateResult.keep_running;
    }

    fn renderVideo(_: *GameState) void {}

    fn renderAudio(_: *GameState) void {}

    fn deinit(_: *GameState) void {
        std.debug.print("Goodbye from game\n", .{});
    }
};

export fn gameInit(allocator: *const std.mem.Allocator) *anyopaque {
    const game_state = allocator.create(GameState) catch @panic("out of memory.");
    game_state.init();
    return game_state;
}

export fn gameReload(game_state_ptr: *anyopaque) void {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    game_state.reload();
}

export fn gameReceiveEvent(game_state_ptr: *anyopaque, event: *const platform.Event) void {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    game_state.receiveEvent(event);
}

export fn gameUpdate(game_state_ptr: *anyopaque) platform.UpdateResult {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    return game_state.update();
}

export fn gameRenderVideo(game_state_ptr: *anyopaque) void {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    game_state.renderVideo();
}

export fn gameRenderAudio(game_state_ptr: *anyopaque) void {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    game_state.renderAudio();
}

export fn gameDeinit(game_state_ptr: *anyopaque) void {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    game_state.deinit();
}
