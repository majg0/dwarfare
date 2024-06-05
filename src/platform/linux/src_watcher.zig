const std = @import("std");

const linux = std.os.linux;
const IN = linux.IN;

pub const SrcWatcher = struct {
    const Self = @This();

    event_buf: [4096]u8 align(@alignOf(linux.inotify_event)) = undefined,
    fd: i32,
    wd: i32,

    fn init(self: *Self, pathname: [*:0]const u8) void {
        self.fd = @intCast(linux.inotify_init1(IN.NONBLOCK | IN.CLOEXEC));
        // TODO: walk directory tree and listen all folders
        self.wd = @intCast(linux.inotify_add_watch(
            self.fd,
            pathname,
            IN.MODIFY,
        ));
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
