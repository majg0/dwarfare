const std = @import("std");

const serialization_endianness = std.builtin.Endian.big;

pub fn serialize(stream: *std.io.StreamSource, value: anytype) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        // Type: void,
        // Void: void,
        // Bool: void,
        // NoReturn: void,
        .Int => {
            try stream.writer().writeInt(T, value, serialization_endianness);
        },
        .Float => |f| {
            try stream.writer().writeInt(
                switch (f.bits) {
                    32 => u32,
                    64 => u64,
                    else => @compileError(
                        std.fmt.comptimePrint("Unable to serialize f{s}\n", .{@typeName(T)}),
                    ),
                },
                @bitCast(value),
                .big,
            );
        },
        // Pointer: Pointer,
        // Array: Array,
        // Struct: Struct,
        // ComptimeFloat: void,
        // ComptimeInt: void,
        // Undefined: void,
        // Null: void,
        // Optional: Optional,
        // ErrorUnion: ErrorUnion,
        // ErrorSet: ErrorSet,
        .Enum => {
            const int = @intFromEnum(value);
            try stream.writer().writeInt(@TypeOf(int), int, serialization_endianness);
        },
        // Union: Union,
        // Fn: Fn,
        // Opaque: Opaque,
        // Frame: Frame,
        // AnyFrame: AnyFrame,
        // Vector: Vector,
        // EnumLiteral: void,
        else => @compileError(
            std.fmt.comptimePrint("Unable to serialize {s}\n", .{@typeName(T)}),
        ),
    }
}

pub fn deserialize(stream: *std.io.StreamSource, comptime T: type) !T {
    switch (@typeInfo(T)) {
        // Type: void,
        // Void: void,
        // Bool: void,
        // NoReturn: void,
        .Float => |f| {
            return @bitCast(try stream.reader().readInt(
                switch (f.bits) {
                    32 => u32,
                    64 => u64,
                    else => @compileError(
                        std.fmt.comptimePrint("Unable to deserialize f{s}\n", .{@typeName(T)}),
                    ),
                },
                serialization_endianness,
            ));
        },
        .Int => {
            return try stream.reader().readInt(T, serialization_endianness);
        },
        // Pointer: Pointer,
        // Array: Array,
        // Struct: Struct,
        // ComptimeFloat: void,
        // ComptimeInt: void,
        // Undefined: void,
        // Null: void,
        // Optional: Optional,
        // ErrorUnion: ErrorUnion,
        // ErrorSet: ErrorSet,
        .Enum => {
            return @enumFromInt(try stream.reader().readInt(
                @Type(.{ .Int = .{ .signedness = .unsigned, .bits = @bitSizeOf(T) } }),
                serialization_endianness,
            ));
        },
        // Union: Union,
        // Fn: Fn,
        // Opaque: Opaque,
        // Frame: Frame,
        // AnyFrame: AnyFrame,
        // Vector: Vector,
        // EnumLiteral: void,
        else => @compileError(
            std.fmt.comptimePrint("Unable to deserialize {s}\n", .{@typeName(T)}),
        ),
    }
}

test "stream" {
    const t = std.testing;

    var buf = std.mem.zeroes([128:0]u8);

    var w = std.io.StreamSource{
        .buffer = std.io.fixedBufferStream(buf[0..]),
    };

    var r = std.io.StreamSource{
        .buffer = std.io.fixedBufferStream(buf[0..]),
    };

    inline for (
        .{
            @as(u32, 8),
            @as(f64, 1.3),
            @as(f32, 2.4),
            (enum(u8) { hi, yo, sup }).sup,
        },
    ) |input| {
        try serialize(&w, input);
        const output = try deserialize(&r, @TypeOf(input));
        try t.expectEqual(input, output);
    }
}
