const std = @import("std");
const builtin = @import("builtin");
const consts = @import("./consts.zig");

const assert = std.debug.assert;

const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("errno.h");
});

const GameLoader = struct {
    const GameStatePtr = *anyopaque;
    const path_len_max = std.fs.max_path_bytes;

    path_buf: [path_len_max:0]u8,
    path: []u8,

    lib: ?std.DynLib,

    game_state: GameStatePtr,
    gameInit: *const fn (*const std.mem.Allocator) GameStatePtr,
    gameReload: *const fn (GameStatePtr) void,
    gameTick: *const fn (GameStatePtr) void,
    gameRenderVideo: *const fn (GameStatePtr) void,
    gameRenderAudio: *const fn (GameStatePtr) void,

    fn init(self: *GameLoader, allocator: *const std.mem.Allocator) std.DynLib.Error!void {
        {
            const lib_dir = switch (builtin.mode) {
                .Debug => if (builtin.os.tag == .windows) "zig-out/bin/" else "zig-out/lib/",
                else => @compileError("Where will the game library reside relative to the loader?"),
            };
            const lib_name = switch (builtin.os.tag) {
                .linux => "libgame.so",
                .macos => "libgame.dylib",
                .windows => "game.dll",
                else => @compileError("What is the game library called on this os?"),
            };
            const path = lib_dir ++ lib_name;

            self.path_buf = std.mem.zeroes([path_len_max:0]u8);
            if (std.fs.path.isAbsolute(path)) {
                assert(path.len >= path_len_max);
                @memcpy(&self.path_buf, path.ptr);
            } else {
                self.path = std.fs.realpath(path, &self.path_buf) catch unreachable;
            }
        }
        try self.lib_load();
        self.game_state = self.gameInit(allocator);
    }

    fn tick(self: *GameLoader) void {
        self.gameTick(self.game_state);
    }
    fn renderVideo(self: *GameLoader) void {
        self.gameRenderVideo(self.game_state);
    }
    fn renderAudio(self: *GameLoader) void {
        self.gameRenderAudio(self.game_state);
    }

    fn lib_load(self: *GameLoader) std.DynLib.Error!void {
        self.lib = try std.DynLib.open(self.path);
        self.gameInit = self.lib.?.lookup(@TypeOf(self.gameInit), "gameInit") orelse unreachable;
        self.gameReload = self.lib.?.lookup(@TypeOf(self.gameReload), "gameReload") orelse unreachable;
        self.gameTick = self.lib.?.lookup(@TypeOf(self.gameTick), "gameTick") orelse unreachable;
        self.gameRenderVideo = self.lib.?.lookup(@TypeOf(self.gameRenderVideo), "gameRenderVideo") orelse unreachable;
        self.gameRenderAudio = self.lib.?.lookup(@TypeOf(self.gameRenderAudio), "gameRenderAudio") orelse unreachable;
    }

    fn recompileAndReload(self: *GameLoader, allocator: *const std.mem.Allocator) (std.process.Child.SpawnError || std.DynLib.Error)!void {
        if (builtin.mode == .Debug) {
            self.lib_unload();
            {
                var game_compile = std.process.Child.init(
                    &.{ "zig", "build", "-Dgame_only=true" },
                    allocator.*,
                );
                _ = try game_compile.spawnAndWait();
            }
            try self.lib_load();
            self.gameReload(self.game_state);
        }
    }

    fn lib_unload(self: *GameLoader) void {
        if (self.lib) |*dyn| {
            dyn.close();
        }
    }
};

pub fn main() !void {
    // mem

    // TODO: create a one-time allocator, which we lock immediately to ensure a single allocation
    // TODO: override libc's allocator
    const page_allocator = std.heap.page_allocator;
    var logger = std.heap.loggingAllocator(page_allocator);
    // TODO: maybe don't use Arena, as it increases memory usage by 50% (yes, really...)
    var arena = std.heap.ArenaAllocator.init(logger.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    // game loader
    var game_loader: GameLoader = undefined;
    try game_loader.init(&allocator);
    defer game_loader.lib_unload();

    // src watcher
    for (0..300) |i| {
        if ((i % 50) == 0) {
            try game_loader.recompileAndReload(&allocator);
        }
        // TODO: proper loop
        game_loader.tick();
        game_loader.renderVideo();
        game_loader.renderAudio();
        std.time.sleep(1e8);
    }
}
