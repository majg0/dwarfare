const std = @import("std");
const assert = std.debug.assert;

const Stream = std.io.FixedBufferStream([]u8);
const WriteError = Stream.Writer.Error;
const ReadError = Stream.Reader.NoEofError;
const SerializationPath = enum {
    read,
    write,
};
fn SyncError(comptime path: SerializationPath) type {
    return switch (path) {
        .read => ReadError,
        .write => WriteError,
    };
}
const serialization_endianness = std.builtin.Endian.big;

pub const Serializer = struct {
    const BitWriter = std.io.BitWriter(serialization_endianness, Stream.Writer);

    const path = SerializationPath.write;

    bit_rw: *BitWriter,

    pub fn init(w: *BitWriter) Serializer {
        return Serializer{ .bit_rw = w };
    }

    pub fn sync(self: *Serializer, value: anytype) WriteError!void {
        return syncGeneric(self, value);
    }
};

pub const Deserializer = struct {
    const BitReader = std.io.BitReader(serialization_endianness, Stream.Reader);

    const path = SerializationPath.read;

    bit_rw: *BitReader,

    pub fn init(r: *BitReader) Deserializer {
        return Deserializer{ .bit_rw = r };
    }

    pub fn sync(self: *Deserializer, value: anytype) ReadError!void {
        return syncGeneric(self, value);
    }
};

inline fn syncGeneric(synchronizer: anytype, value: anytype) SyncError(@TypeOf(synchronizer.*).path)!void {
    assert(@typeInfo(@TypeOf(synchronizer)) == .Pointer);
    const path = comptime @TypeOf(synchronizer.*).path;
    const T = if (@typeInfo(@TypeOf(value)) == .Pointer)
        @typeInfo(@TypeOf(value)).Pointer.child
    else
        @TypeOf(value);
    switch (@typeInfo(T)) {
        .Int, .ComptimeInt, .Float, .ComptimeFloat => @compileError(std.fmt.comptimePrint(
            "syncGeneric is not implemented for types which require constraints; instead, bake the values into structs with constraint metadata",
            .{@typeName(T)},
        )),
        .Bool => {
            try syncBool(synchronizer.bit_rw, path, value);
        },
        .Enum => {
            try syncEnum(synchronizer.bit_rw, path, T, value);
        },
        .Struct => {
            assert(@typeInfo(@TypeOf(value)) == .Pointer);
            try syncStruct(synchronizer.bit_rw, path, T, value);
        },
        .Union => {
            assert(@typeInfo(@TypeOf(value)) == .Pointer);
            try syncUnion(synchronizer.bit_rw, path, T, value);
        },
        else => @compileError(std.fmt.comptimePrint(
            "syncGeneric not implemented for type {s}",
            .{@typeName(T)},
        )),
    }
}

inline fn syncStruct(
    stream: anytype,
    comptime path: SerializationPath,
    comptime T: type,
    value: if (path == .write) *const T else *T,
) SyncError(path)!void {
    inline for (@typeInfo(T).Struct.fields) |field| {
        switch (@typeInfo(field.type)) {
            .Int => {
                const field_value = switch (path) {
                    .read => &@field(value, field.name),
                    .write => @field(value, field.name),
                };
                const min = @field(T, field.name ++ "_min");
                const max = @field(T, field.name ++ "_max");
                try syncInt(stream, path, field.type, field_value, min, max);
            },
            .Float => {
                const field_value = switch (path) {
                    .read => &@field(value, field.name),
                    .write => @field(value, field.name),
                };
                const min = @field(T, field.name ++ "_min");
                const max = @field(T, field.name ++ "_max");
                const res = @field(T, field.name ++ "_res");
                try syncFloat(stream, path, field.type, field_value, min, max, res);
            },
            .Enum => {
                const field_value = switch (path) {
                    .read => &@field(value, field.name),
                    .write => @field(value, field.name),
                };
                try syncEnum(stream, path, field.type, field_value);
            },
            .Struct => {
                const field_value = &@field(value, field.name);
                try syncStruct(stream, path, field.type, field_value);
            },
            else => @compileError(std.fmt.comptimePrint(
                "syncStruct not implemented for field of type {s}",
                .{@typeName(field.type)},
            )),
        }
    }
}

test "struct" {
    const t = std.testing;

    var buf = std.mem.zeroes([8:0]u8);

    var w_stream = std.io.fixedBufferStream(buf[0..]);
    var w = std.io.bitWriter(serialization_endianness, w_stream.writer());

    var r_stream = std.io.fixedBufferStream(buf[0..]);
    var r = std.io.bitReader(serialization_endianness, r_stream.reader());

    const E = enum(u8) { no, maybe, yes };
    const S2 = struct {
        e: E,
    };
    const S1 = struct {
        const u_min = 2;
        const u_max = 4;

        const i_min = -4;
        const i_max = 3;

        const f_min = 0.0;
        const f_max = 1.0;
        const f_res = 0.01;

        u: u8,
        i: i16,
        f: f32,
        s: S2,
    };

    const inputs = [_]S1{
        S1{ .u = 2, .i = -2, .f = 0.00, .s = .{ .e = .no } },
        S1{ .u = 3, .i = -4, .f = 0.16, .s = .{ .e = .maybe } },
        S1{ .u = 4, .i = 3, .f = 1.00, .s = .{ .e = .yes } },
    };

    // concrete
    {
        inline for (inputs, 0..) |input, i| {
            try syncStruct(&w, .write, S1, &input);
            try t.expectEqual((2 + 3 + 7 + 2) * (i + 1), w_stream.pos * 8 + w.bit_count);
        }

        try w.flushBits();

        inline for (inputs) |input| {
            var output: S1 = undefined;
            try syncStruct(&r, .read, S1, &output);
            try t.expectEqual(input, output);
        }
    }

    // generic
    {
        w_stream.reset();
        r_stream.reset();
        r.bit_count = 0;

        var s = Serializer.init(&w);

        inline for (inputs, 0..) |input, i| {
            try s.sync(&input);
            try t.expectEqual((2 + 3 + 7 + 2) * (i + 1), w_stream.pos * 8 + w.bit_count);
        }

        try w.flushBits();

        var d = Deserializer.init(&r);

        inline for (inputs) |input| {
            var output: S1 = undefined;
            try d.sync(&output);
            try t.expectEqual(input, output);
        }
    }
}

inline fn syncEnum(
    stream: anytype,
    comptime path: SerializationPath,
    comptime T: type,
    value: if (path == .write) T else *T,
) SyncError(path)!void {
    assert(@typeInfo(T) == .Enum);

    const e = @typeInfo(T).Enum;
    const V = e.tag_type;
    var min: V = e.fields[0].value;
    var max: V = 0;
    inline for (e.fields) |field| {
        min = @min(field.value, min);
        max = @max(field.value, max);
    }

    switch (path) {
        .read => {
            var int: V = min;
            try syncInt(stream, .read, V, &int, min, max);
            assert(int >= min);
            assert(int <= max);
            value.* = @enumFromInt(int);
        },
        .write => {
            const int: V = @intFromEnum(value);
            assert(int >= min);
            assert(int <= max);
            try syncInt(stream, .write, V, int, min, max);
        },
    }
}

test "enum" {
    const t = std.testing;

    var buf = std.mem.zeroes([8:0]u8);

    var w_stream = std.io.fixedBufferStream(buf[0..]);
    var w = std.io.bitWriter(serialization_endianness, w_stream.writer());

    var r_stream = std.io.fixedBufferStream(buf[0..]);
    var r = std.io.bitReader(serialization_endianness, r_stream.reader());

    const Foo = enum(u8) {
        zero = 5,
        one,
    };

    const inputs = [8]Foo{ .zero, .one, .zero, .zero, .one, .zero, .one, .one };

    // concrete
    {
        inline for (inputs) |input| {
            try syncEnum(&w, .write, Foo, input);
        }

        try t.expectEqual(8, w_stream.pos * 8 + w.bit_count);
        try t.expectEqual(0b01001011, buf[0]);

        inline for (inputs) |input| {
            var output: Foo = undefined;
            try syncEnum(&r, .read, Foo, &output);
            try t.expectEqual(input, output);
        }
    }

    // generic
    {
        w_stream.reset();
        r_stream.reset();

        var s = Serializer.init(&w);

        inline for (inputs) |input| {
            try s.sync(input);
        }

        try t.expectEqual(8, w_stream.pos * 8 + w.bit_count);
        try t.expectEqual(0b01001011, buf[0]);

        var d = Deserializer.init(&r);

        inline for (inputs) |input| {
            var output: Foo = undefined;
            try d.sync(&output);
            try t.expectEqual(input, output);
        }
    }
}

inline fn syncUnion(
    stream: anytype,
    comptime path: SerializationPath,
    comptime T: type,
    value: if (path == .write) *const T else *T,
) SyncError(path)!void {
    const TagEnum = @typeInfo(T).Union.tag_type orelse @compileError(
        "Unable to bitpack the plain union " ++ @typeName(T) ++ "; Use a tagged union instead?",
    );

    // tag
    var tag: TagEnum = undefined;
    {
        switch (path) {
            .write => {
                tag = value.*;
                try syncEnum(stream, path, TagEnum, tag);
            },
            .read => {
                try syncEnum(stream, path, TagEnum, &tag);
            },
        }
    }

    // payload
    {
        switch (tag) {
            inline else => |tag_comptime| {
                const field = comptime std.meta.fields(T)[std.meta.fieldIndex(T, @tagName(tag_comptime)).?];
                var payload: field.type = undefined;

                if (path == .write) {
                    switch (value.*) {
                        tag_comptime => |value_payload| {
                            payload = value_payload;
                        },
                        else => {},
                    }
                }

                switch (@typeInfo(field.type)) {
                    .Int => {
                        const min = @field(T, field.name ++ "_min");
                        const max = @field(T, field.name ++ "_max");
                        try syncInt(stream, path, field.type, if (path == .read) &payload else payload, min, max);
                    },
                    .Float => {
                        const min = @field(T, field.name ++ "_min");
                        const max = @field(T, field.name ++ "_max");
                        const res = @field(T, field.name ++ "_res");
                        try syncFloat(stream, path, field.type, if (path == .read) &payload else payload, min, max, res);
                    },
                    .Enum => {
                        try syncEnum(stream, path, field.type, if (path == .read) &payload else payload);
                    },
                    .Struct => {
                        try syncStruct(stream, path, field.type, &payload);
                    },
                    else => @compileError(std.fmt.comptimePrint(
                        "syncUnion not implemented for field of type {s}",
                        .{@typeName(field.type)},
                    )),
                }

                if (path == .read) {
                    value.* = @unionInit(T, field.name, payload);
                }
            },
        }
    }
}

test "union" {
    const t = std.testing;

    var buf = std.mem.zeroes([8:0]u8);

    var w_stream = std.io.fixedBufferStream(buf[0..]);
    var w = std.io.bitWriter(serialization_endianness, w_stream.writer());

    var r_stream = std.io.fixedBufferStream(buf[0..]);
    var r = std.io.bitReader(serialization_endianness, r_stream.reader());

    // 3 bits
    const Tag = enum(u8) {
        u = 4,
        f = 6,
        s = 8,
    };

    // 1 bit
    const S = struct {
        const u_min = 0;
        const u_max = 1;

        u: u8,
    };

    const U = union(Tag) {
        // 2 bits
        const u_min = 0;
        const u_max = 3;

        // 20 bits
        const f_min = 0;
        const f_max = 1000;
        const f_res = 0.001;

        u: u8, // 3 + 2 = 5
        f: f64, // 3 + 20 = 23
        s: S, // 3 + 1 = 4
    };

    const inputs = [_]U{
        .{ .u = 1 },
        .{ .u = 3 },
        .{ .f = 123.456 },
        .{ .f = 789 },
        .{ .s = .{ .u = 1 } },
        .{ .s = .{ .u = 0 } },
    };
    const offsets = [_]usize{ 5, 10, 33, 56, 60, 64 };

    // concrete
    {
        inline for (inputs, offsets) |input, offset| {
            try syncUnion(&w, .write, U, &input);
            try t.expectEqual(offset, w_stream.pos * 8 + w.bit_count);
        }

        inline for (inputs) |input| {
            var output: U = undefined;
            try syncUnion(&r, .read, U, &output);
            try t.expectEqual(input, output);
        }
    }

    // generic
    {
        w_stream.reset();
        r_stream.reset();

        var s = Serializer.init(&w);

        inline for (inputs, offsets) |input, offset| {
            try s.sync(&input);
            try t.expectEqual(offset, w_stream.pos * 8 + w.bit_count);
        }

        var d = Deserializer.init(&r);

        inline for (inputs) |input| {
            var output: U = undefined;
            try d.sync(&output);
            try t.expectEqual(input, output);
        }
    }
}

inline fn syncFloat(
    stream: anytype,
    comptime path: SerializationPath,
    comptime T: type,
    value: if (path == .write) T else *T,
    min: T,
    max: T,
    res: T,
) SyncError(path)!void {
    assert(@typeInfo(T) == .Float);
    assert(min < max);
    assert(res > 0);

    const delta = max - min;
    const steps = @ceil(delta / res);
    const int_max: u64 = @intFromFloat(steps);

    switch (path) {
        .read => {
            {
                var int: u64 = 0;
                try syncInt(stream, .read, u64, &int, 0, int_max);
                const normalized = @as(T, @floatFromInt(int)) / steps;
                value.* = normalized * delta + min;
            }
            assert(value.* >= min);
            assert(value.* <= max);
        },
        .write => {
            assert(value >= min);
            assert(value <= max);
            {
                const normalized = std.math.clamp((value - min) / delta, 0, 1);
                const int: u64 = @intFromFloat(@floor(normalized * steps + 0.5));
                try syncInt(stream, .write, u64, int, 0, int_max);
            }
        },
    }
}

test "float" {
    const t = std.testing;

    var buf = std.mem.zeroes([8:0]u8);

    var w_stream = std.io.fixedBufferStream(buf[0..]);
    var w = std.io.bitWriter(serialization_endianness, w_stream.writer());

    var r_stream = std.io.fixedBufferStream(buf[0..]);
    var r = std.io.bitReader(serialization_endianness, r_stream.reader());

    const types = .{ f32, f16, f32, f64 };
    const inputs = .{ 1.3, 3, -1.14, -2.13 };
    const expecteds = .{ 1.3, 3, -1.1, -2.25 };
    const mins = .{ 1, 2, -3, -3 };
    const maxs = .{ 3, 3, -1, -2 };
    const ress = .{ 0.1, 0.25, 0.1, 0.25 };

    inline for (types, inputs, mins, maxs, ress) |T, input, min, max, res| {
        try syncFloat(&w, .write, T, input, min, max, res);
    }

    try t.expectEqual(16, w_stream.pos * 8 + w.bit_count);
    try t.expectEqual(0b00011_100, buf[0]);
    try t.expectEqual(0b10011_011, buf[1]);

    inline for (types, expecteds, mins, maxs, ress) |T, expected, min, max, res| {
        var output: T = undefined;
        try syncFloat(&r, .read, T, &output, min, max, res);
        try t.expectEqual(expected, output);
    }
}

inline fn syncInt(
    stream: anytype,
    comptime path: SerializationPath,
    comptime T: type,
    value: if (path == .write) T else *T,
    min: T,
    max: T,
) SyncError(path)!void {
    assert(@typeInfo(T) == .Int);
    assert(min < max);

    const bit_count = bitsRequired(max - min);

    const Unsigned = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = @typeInfo(T).Int.bits } });

    switch (path) {
        .write => {
            assert(value >= min);
            assert(value <= max);
            const unsigned_value = @as(Unsigned, @intCast(value - min));
            try stream.writeBits(unsigned_value, bit_count);
        },
        .read => {
            const unsigned_value = try stream.readBitsNoEof(Unsigned, bit_count);
            value.* = min + @as(T, @intCast(unsigned_value));
            assert(value.* >= min);
            assert(value.* <= max);
        },
    }
}

test "int" {
    const t = std.testing;

    var buf = std.mem.zeroes([8:0]u8);

    var w_stream = std.io.fixedBufferStream(buf[0..]);
    var w = std.io.bitWriter(serialization_endianness, w_stream.writer());

    var r_stream = std.io.fixedBufferStream(buf[0..]);
    var r = std.io.bitReader(serialization_endianness, r_stream.reader());

    const types = .{ u8, u16, u32, i64 };
    const inputs = .{ 1, 2, 7, -1 };
    const mins = .{ 0, 0, 4, -4 };
    const maxs = .{ 1, 2, 7, 3 };

    inline for (types, inputs, mins, maxs) |T, input, min, max| {
        try syncInt(&w, .write, T, input, min, max);
    }

    try t.expectEqual(8, w_stream.pos * 8 + w.bit_count);
    try t.expectEqual(0b1_10_11_011, buf[0]);

    inline for (types, inputs, mins, maxs) |T, input, min, max| {
        var output: T = undefined;
        try syncInt(&r, .read, T, &output, min, max);
        try t.expectEqual(input, output);
    }
}

inline fn syncBool(
    stream: anytype,
    comptime path: SerializationPath,
    value: if (path == .write) bool else *bool,
) SyncError(path)!void {
    switch (path) {
        .write => {
            try stream.writeBits(@intFromBool(value), 1);
        },
        .read => {
            const unsigned_value = try stream.readBitsNoEof(u1, 1);
            value.* = unsigned_value == 1;
        },
    }
}

test "bool" {
    const t = std.testing;

    var buf = std.mem.zeroes([8:0]u8);

    var w_stream = std.io.fixedBufferStream(buf[0..]);
    var w = std.io.bitWriter(serialization_endianness, w_stream.writer());

    var r_stream = std.io.fixedBufferStream(buf[0..]);
    var r = std.io.bitReader(serialization_endianness, r_stream.reader());

    const inputs = .{ true, false, true, false, true, true, false, false };

    // raw
    {
        inline for (inputs) |input| {
            try syncBool(&w, .write, input);
        }

        try t.expectEqual(8, w_stream.pos * 8 + w.bit_count);
        try t.expectEqual(0b10101100, buf[0]);

        inline for (inputs) |input| {
            var output: bool = undefined;
            try syncBool(&r, .read, &output);
            try t.expectEqual(input, output);
        }
    }

    // generic
    {
        w_stream.reset();
        r_stream.reset();

        var s = Serializer.init(&w);

        inline for (inputs) |input| {
            try s.sync(input);
        }

        try t.expectEqual(8, w_stream.pos * 8 + w.bit_count);
        try t.expectEqual(0b10101100, buf[0]);

        var d = Deserializer.init(&r);

        inline for (inputs) |input| {
            var output: bool = undefined;
            try d.sync(&output);
            try t.expectEqual(input, output);
        }
    }
}

inline fn bitsRequired(value: anytype) usize {
    assert(value >= 0);
    switch (@typeInfo(@TypeOf(value))) {
        .Int => |int| {
            return int.bits - @clz(value);
        },
        .ComptimeInt => {
            assert(value >= 0);
            return 128 - @clz(@as(u128, value));
        },
        else => unreachable,
    }
}

test "bits_required" {
    const t = std.testing;

    try t.expectEqual(0, bitsRequired(0));
    try t.expectEqual(1, bitsRequired(1));
    inline for (2..128) |i| {
        try t.expectEqual(i, bitsRequired(1 << (i - 1)));
        try t.expectEqual(i, bitsRequired((1 << i) - 1));
    }
}
