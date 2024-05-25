const std = @import("std");

const GameState = struct {
    reload_count: usize,
    tick_current: usize,

    fn init(self: *GameState) void {
        self.reload_count = 0;
        self.tick_current = 0;
    }

    fn reload(self: *GameState) void {
        self.reload_count += 1;
        std.debug.print("Reload {}\n", .{self.reload_count});
    }

    fn tick(self: *GameState) void {
        defer self.tick_current += 1;
        std.debug.print("Tick {}\n", .{self.tick_current});
    }

    fn renderVideo(_: *GameState) void {}

    fn renderAudio(_: *GameState) void {}
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

export fn gameTick(game_state_ptr: *anyopaque) void {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    game_state.tick();
}

export fn gameRenderVideo(game_state_ptr: *anyopaque) void {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    game_state.renderVideo();
}

export fn gameRenderAudio(game_state_ptr: *anyopaque) void {
    var game_state: *GameState = @ptrCast(@alignCast(game_state_ptr));
    game_state.renderAudio();
}
