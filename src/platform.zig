const std = @import("std");
const builtin = @import("builtin");

const assert = std.debug.assert;

fn SrcWatcher() type {
    const enabled = comptime builtin.os.tag == .linux and builtin.mode == .Debug;
    if (!enabled) {
        return struct {};
    }

    const linux = std.os.linux;
    const IN = linux.IN;
    return struct {
        const Self = @This();

        event_buf: [4096]u8 align(@alignOf(linux.inotify_event)) = undefined,
        fd: i32,
        wd: i32,

        fn init() Self {
            const fd: i32 = @intCast(linux.inotify_init1(IN.NONBLOCK | IN.CLOEXEC));
            // TODO: walk directory tree and listen all folders
            const wd: i32 = @intCast(linux.inotify_add_watch(
                fd,
                "src",
                IN.MODIFY,
            ));
            return .{
                .fd = fd,
                .wd = wd,
            };
        }

        fn change_detected(self: *Self) bool {
            const bytes_read = linux.read(
                self.fd,
                &self.event_buf,
                self.event_buf.len,
            );

            var ptr: [*]u8 = &self.event_buf;
            const ptr_end = ptr + bytes_read;
            while (@intFromPtr(ptr) < @intFromPtr(ptr_end)) {
                const event = @as(*linux.inotify_event, @ptrCast(@alignCast(ptr)));
                if ((event.mask & IN.MODIFY) != 0) {
                    return true;
                }
                ptr = @alignCast(ptr + @sizeOf(linux.inotify_event) + event.len);
            }

            return false;
        }

        fn deinit(self: *const Self) void {
            _ = linux.inotify_rm_watch(self.fd, self.wd);
            _ = linux.close(self.fd);
        }
    };
}

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

    fn init(self: *GameLoader, path: []const u8, allocator: *const std.mem.Allocator) std.DynLib.Error!void {
        self.path_buf = std.mem.zeroes([path_len_max:0]u8);
        if (std.fs.path.isAbsolute(path)) {
            assert(path.len >= path_len_max);
            @memcpy(&self.path_buf, path.ptr);
        } else {
            self.path = std.fs.realpath(path, &self.path_buf) catch unreachable;
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

    fn recompileAndReload(self: *GameLoader, allocator: *const std.mem.Allocator) (std.ChildProcess.SpawnError || std.DynLib.Error)!void {
        if (builtin.mode == .Debug) {
            {
                var game_compile = std.ChildProcess.init(
                    &.{ "zig", "build", "-Dgame_only=true" },
                    allocator.*,
                );
                _ = try game_compile.spawnAndWait();
            }
            self.lib_unload();
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

    const page_allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    // NOTE: pre-allocate 1 GiB; we should never have to touch it again
    {
        const pages = try allocator.alignedAlloc(u8, std.mem.page_size, 1 * 1024 * 1024 * 1024);
        allocator.free(pages);
    }

    // game loader
    var game_loader: GameLoader = undefined;
    {
        const lib_dir = switch (builtin.mode) {
            .Debug => "zig-out/lib/",
            else => @compileError("where will the game library reside relative to the loader?"),
        };
        const lib_name = switch (builtin.os.tag) {
            .linux => "libdwarfare.so",
            else => @compileError("what is the game library called on this os?"),
        };
        const path = lib_dir ++ lib_name;
        try game_loader.init(path, &allocator);
    }
    defer game_loader.lib_unload();

    // src watcher
    var src_watcher = SrcWatcher().init();
    defer src_watcher.deinit();

    for (0..1e3) |_| {
        if (src_watcher.change_detected()) {
            try game_loader.recompileAndReload(&allocator);
        }
        game_loader.tick();
        game_loader.renderVideo();
        game_loader.renderAudio();
        std.time.sleep(1e8);
    }
}
