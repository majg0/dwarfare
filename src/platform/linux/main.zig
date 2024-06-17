const std = @import("std");
const dwarven = @cImport(@cInclude("dwarven.h"));
const xcb = @import("./xcb.zig");

export fn platformExit(exit_code: i32) void {
    std.os.linux.exit(exit_code);
}

pub fn main() !void {
    var xcb_ui: xcb.XcbUi = undefined;
    try xcb_ui.init();
    defer xcb_ui.kill();

    dwarven.init();

    loop: while (true) {
        while (xcb_ui.eventsPoll()) |event| {
            dwarven.receiveEvent(@ptrCast(@constCast(&event)));
        }
        if (dwarven.update() != 0) {
            break :loop;
        }
    }

    dwarven.kill();
}
