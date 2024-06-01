const std = @import("std");

export fn init() c_int {
    std.debug.print("Platform init!", .{});
    return 0;
}

export fn kill() c_int {
    std.debug.print("Platform kill!", .{});
    return 0;
}
