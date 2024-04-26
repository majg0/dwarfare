const std = @import("std");
const assert = std.debug.assert;

pub fn parse(args: *std.process.ArgIterator, comptime T: type) ?T {
    // NOTE: skip executable name
    assert(args.skip());
    return parseAny(args, T) orelse {
        std.io.getStdErr().writeAll(T.help) catch {};
        return null;
    };
}

fn parseAny(args: *std.process.ArgIterator, comptime T: type) ?T {
    return switch (@typeInfo(T)) {
        .Union => parseCommand(args, T),
        .Struct => parseFlags(args, T),
        else => null,
    };
}

fn parseCommand(args: *std.process.ArgIterator, comptime T: type) ?T {
    comptime assert(@typeInfo(T) == .Union);

    const command = args.next() orelse {
        return null;
    };

    inline for (comptime std.meta.fields(T)) |field| {
        if (std.mem.eql(u8, command, field.name)) {
            return @unionInit(
                T,
                field.name,
                parseAny(args, field.type) orelse {
                    return null;
                },
            );
        }
    }

    return null;
}

fn parseFlags(args: *std.process.ArgIterator, comptime T: type) ?T {
    if (T == void) {
        return .{};
    }

    assert(@typeInfo(T) == .Struct);
    assert(args.next() == null);

    return .{};
}
