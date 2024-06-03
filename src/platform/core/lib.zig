const std = @import("std");

export fn init() void {
    std.debug.print("Platform init!\n", .{});
}

export fn kill() void {
    std.debug.print("Platform kill!\n", .{});
}
