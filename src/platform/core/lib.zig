const std = @import("std");
const p = std.debug.print;

extern fn platformExit(exit_code: i32) void;

export fn init() void {
    p("dwarven.init\n", .{});
}

export fn kill() void {
    p("dwarven.kill\n", .{});
}

export fn onWindowClose(_: *anyopaque) void {
    platformExit(0);
}
