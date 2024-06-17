const std = @import("std");
const builtin = @import("builtin");
const common = @import("./common.zig");

const Allocator = std.mem.Allocator;
const p = std.debug.print;
const assert = std.debug.assert;

const GameLoader = @import("./GameLoader.zig");

extern fn platformExit(exit_code: i32) void;

var game_loader: GameLoader = undefined;

export fn init() void {
    game_loader.init("game", &std.heap.page_allocator) catch {};
}

export fn update() common.UpdateResult {
    return game_loader.update();
}

export fn receiveEvent(event: *const common.Event) void {
    game_loader.receiveEvent(event);
}

export fn kill() void {
    game_loader.lib_unload();
}

export fn onWindowClose(_: *anyopaque) void {
    platformExit(0);
}
