const std = @import("std");
const builtin = @import("builtin");
const common = @import("./common.zig");
const assert = std.debug.assert;

const GameLoader = @This();
const GameStatePtr = *anyopaque;
const path_len_max = std.fs.max_path_bytes;

path_buf: [path_len_max:0]u8,
path: []u8,

lib: ?std.DynLib,

game_state: GameStatePtr,
gameInit: *const fn (*const std.mem.Allocator) GameStatePtr,
gameReload: *const fn (GameStatePtr) void,
gameReceiveEvent: *const fn (GameStatePtr, *const common.Event) void,
gameUpdate: *const fn (GameStatePtr) common.UpdateResult,
gameRenderVideo: *const fn (GameStatePtr) void,
gameRenderAudio: *const fn (GameStatePtr) void,
gameDeinit: *const fn (GameStatePtr) void,

pub fn init(self: *GameLoader, name: []const u8, allocator: *const std.mem.Allocator) std.DynLib.Error!void {
    {
        self.path_buf = std.mem.zeroes([path_len_max:0]u8);
        var builder = std.ArrayListUnmanaged(u8).initBuffer(&self.path_buf);

        switch (builtin.mode) {
            .Debug => switch (builtin.os.tag) {
                .windows => {
                    builder.appendSliceAssumeCapacity("zig-out/bin/");
                },
                else => {
                    builder.appendSliceAssumeCapacity("zig-out/lib/");
                },
            },
            else => @compileError("Where will the game library reside relative to the loader?"),
        }

        switch (builtin.os.tag) {
            .linux => {
                builder.appendSliceAssumeCapacity("lib");
                builder.appendSliceAssumeCapacity(name);
                builder.appendSliceAssumeCapacity(".so");
            },
            .macos => {
                builder.appendSliceAssumeCapacity("lib");
                builder.appendSliceAssumeCapacity(name);
                builder.appendSliceAssumeCapacity(".dylib");
            },
            .windows => {
                builder.appendSliceAssumeCapacity(name);
                builder.appendSliceAssumeCapacity(".dll");
            },
            else => @compileError("What is the game library called on this os?"),
        }

        self.path = builder.items;
    }
    try self.lib_load();
    self.game_state = self.gameInit(allocator);
}

pub fn receiveEvent(self: *GameLoader, event: *const common.Event) void {
    return self.gameReceiveEvent(self.game_state, event);
}
pub fn update(self: *GameLoader) common.UpdateResult {
    return self.gameUpdate(self.game_state);
}
pub fn renderVideo(self: *GameLoader) void {
    self.gameRenderVideo(self.game_state);
}
pub fn renderAudio(self: *GameLoader) void {
    self.gameRenderAudio(self.game_state);
}

fn lib_load(self: *GameLoader) std.DynLib.Error!void {
    self.lib = try std.DynLib.open(self.path);
    self.gameInit = self.lib.?.lookup(@TypeOf(self.gameInit), "gameInit") orelse unreachable;
    self.gameReload = self.lib.?.lookup(@TypeOf(self.gameReload), "gameReload") orelse unreachable;
    self.gameReceiveEvent = self.lib.?.lookup(@TypeOf(self.gameReceiveEvent), "gameReceiveEvent") orelse unreachable;
    self.gameUpdate = self.lib.?.lookup(@TypeOf(self.gameUpdate), "gameUpdate") orelse unreachable;
    self.gameRenderVideo = self.lib.?.lookup(@TypeOf(self.gameRenderVideo), "gameRenderVideo") orelse unreachable;
    self.gameRenderAudio = self.lib.?.lookup(@TypeOf(self.gameRenderAudio), "gameRenderAudio") orelse unreachable;
    self.gameDeinit = self.lib.?.lookup(@TypeOf(self.gameDeinit), "gameDeinit") orelse unreachable;
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

pub fn lib_unload(self: *GameLoader) void {
    if (self.lib) |*dyn| {
        self.gameDeinit(self.game_state);
        dyn.close();
    }
}
