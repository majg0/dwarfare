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

        fn poll_writes(self: *Self) bool {
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

const Lib = struct {
    const path_len_max = 256;

    path_buf: [path_len_max:0]u8,
    path: []u8,
    dyn: ?std.DynLib,
    // fingerprint: i128,
    update: *const fn () void = undefined,

    // TODO: or absolute path
    fn init() Lib {
        return Lib{
            .path_buf = std.mem.zeroes([path_len_max:0]u8),
            .path = "",
            .dyn = null,
        };
    }

    fn set_path(lib: *Lib, path: []const u8) void {
        if (std.fs.path.isAbsolute(path)) {
            assert(path.len >= path_len_max);
            @memcpy(&lib.path_buf, path.ptr);
        } else {
            lib.path = std.fs.realpath(path, &lib.path_buf) catch unreachable;
        }
    }

    fn reload(lib: *Lib) std.DynLib.Error!void {
        lib.unload();
        lib.dyn = try std.DynLib.open(lib.path);
        lib.update = lib.dyn.?.lookup(@TypeOf(lib.update), "update") orelse unreachable;
    }

    fn unload(lib: *Lib) void {
        if (lib.dyn) |*dyn| {
            dyn.close();
        }
    }
};

pub fn main() !void {
    // mem
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // io
    const stdout = std.io.getStdOut();
    var bw = std.io.bufferedWriter(stdout.writer());
    const w = bw.writer();

    // game
    const dir_relative = "zig-out/lib/";
    const name = switch (builtin.os.tag) {
        .linux => "libdwarfare.so",
        else => @compileError("what is the game library called on this os?"),
    };
    const path_relative = dir_relative ++ name;
    var lib = Lib.init();
    lib.set_path(path_relative);
    std.debug.print("{s}\n", .{lib.path});
    try lib.reload();
    defer lib.unload();

    // hotswap
    var watcher = SrcWatcher().init();
    defer watcher.deinit();

    for (0..100e1) |i| {
        lib.update();
        if (watcher.poll_writes()) {
            try w.print("Recompiling...\n", .{});
            try bw.flush();
            var cp = std.ChildProcess.init(&.{
                "zig",
                "build",
                "-Dmode=LibOnly",
            }, allocator);
            _ = try cp.spawnAndWait();
            try lib.reload();
        }
        try w.print("{}\n", .{i});
        try bw.flush();
        std.time.sleep(1e8);
    }
}
