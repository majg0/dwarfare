const std = @import("std");
const dwarven = @cImport(@cInclude("dwarven.h"));

export fn platformExit(exit_code: i32) void {
    std.os.linux.exit(exit_code);
}

pub fn main() void {
    dwarven.init(@intCast(std.os.argv.len), @ptrCast(std.os.argv.ptr));
    dwarven.kill();
}
