const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const p = std.debug.print;
const assert = std.debug.assert;

const GameLoader = @import("./GameLoader.zig");

extern fn platformExit(exit_code: i32) void;

// 1. application main happens in the platform-specific executable.
// ^-- macOS & Windows are here
// 2. the executable immediately calls dwarven.init, for maximum flexibility and minimum platform dependence, including CLI args.
// 3. we open the special "game" library, load its functions, and init with a basic one-time page allocator.
// ^-- Linux is here
// 4. we enter the main loop, where the game has complete control over update/render, etc.
// 5. on close requests, we notify the game, and it can decide what to do.

export fn init(argc: i32, argv: [*][*:0]const u8) void {
    p("dwarven.init\n", .{});

    const game_name = std.mem.span(if (argc < 2) "game" else argv[1]);
    p("game name {s}\n", .{game_name});

    var game_loader: GameLoader = undefined;
    game_loader.init(game_name, &std.heap.page_allocator) catch {};
    defer game_loader.lib_unload();

    // TODO: pre-designed update/render loop
}

export fn kill() void {
    p("dwarven.kill\n", .{});
}

export fn onWindowClose(_: *anyopaque) void {
    platformExit(0);
}
