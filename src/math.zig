const std = @import("std");
pub const Real = f32;

pub const Vec2 = @Vector(2, Real);
pub const Vec3 = @Vector(3, Real);
pub const Vec4 = @Vector(4, Real);

/// Column-major (https://en.wikipedia.org/wiki/Row-_and_column-major_order):
/// Code matrices will seem transposed (=reflected over the diagonal) compared to math notation.
pub const Mat4 = @Vector(16, Real);

pub fn col(m: Mat4, index: comptime_int) Vec4 {
    if (index >= 0 and index < 4) {
        return @as(Vec4, m[(4 * index)..(4 * (index + 1))]);
    }
}

pub fn row(m: Mat4, index: comptime_int) Vec4 {
    switch (index) {
        0...3 => {
            const mask = @as(Vec4, @splat(index)) + Vec4{ 0, 4, 8, 12 };
            return @shuffle(
                Real,
                m,
                undefined,
                mask,
            );
        },
        else => @compileError("matrix row index out of bounds"),
    }
}

/// TODO: generalize this to multiplying by a transposed v?
pub fn dot(u: anytype, v: anytype) Real {
    const U = @TypeOf(u);
    const V = @TypeOf(v);
    if (U == Vec4 and V == Vec4) {
        return @reduce(.Add, u * v);
    }
}

fn Mul(comptime U: type, comptime V: type) type {
    if ((U == comptime_float or U == Real) and V == Vec4) return Vec4;
    if (U == Mat4 and V == Vec4) return Vec4;
}

pub fn mul(u: anytype, v: anytype) Mul(@TypeOf(u), @TypeOf(v)) {
    const U = @TypeOf(u);
    const V = @TypeOf(v);
    if ((U == comptime_float or U == Real) and V == Vec4) {
        return @as(Vec4, @splat(u)) * v;
    }
    if (U == Mat4 and V == Vec4) {
        return Vec4{
            dot(row(u, 0), v),
            dot(row(u, 1), v),
            dot(row(u, 2), v),
            dot(row(u, 3), v),
        };
    }
}

/// This differs from textbook examples because we have simplified leveraging r=-l, b=-t
pub fn perspective(fov: Real, aspect: Real, n: Real, f: Real) Mat4 {
    const scale = @tan(fov * 0.5) * n;
    const r = aspect * scale;
    const t = scale;
    return Mat4{
        n / r, 0,     0,                    0,
        0,     n / t, 0,                    0,
        0,     0,     -(f + n) / (f - n),   -1,
        0,     0,     -2 * f * n / (f - n), 0,
    };
}

/// This differs from textbook examples because we have simplified leveraging r=-l, b=-t
pub fn orthographic(width: Real, height: Real, aspect: Real, n: Real, f: Real) Mat4 {
    const scale = @max(width, height);
    const r = aspect * scale;
    const t = scale;
    return Mat4{
        1 / r, 0,     0,                  0,
        0,     1 / t, 0,                  0,
        0,     0,     -2 / (f - n),       0,
        0,     0,     -(f + n) / (f - n), 1,
    };
}

test "linalg" {
    // setup
    const m = Mat4{
        1, 2, 3, 4,
        5, 6, 7, 8,
        4, 3, 2, 1,
        8, 7, 6, 5,
    };
    const u = Vec4{ 1, 2, 3, 4 };
    const v = Vec4{ 2, 3, 4, 1 };
    const s = 1.5;

    // su
    try std.testing.expectEqual(Vec4{ s * u[0], s * u[1], s * u[2], s * u[3] }, mul(s, u));

    // uv
    try std.testing.expectEqual(
        u[0] * v[0] + u[1] * v[1] + u[2] * v[2] + u[3] * v[3],
        dot(u, v),
    );

    // mu
    try std.testing.expectEqual(
        Vec4{
            m[0] * u[0] + m[4] * u[1] + m[8] * u[2] + m[12] * u[3],
            m[1] * u[0] + m[5] * u[1] + m[9] * u[2] + m[13] * u[3],
            m[2] * u[0] + m[6] * u[1] + m[10] * u[2] + m[14] * u[3],
            m[3] * u[0] + m[7] * u[1] + m[11] * u[2] + m[15] * u[3],
        },
        mul(m, u),
    );
}

pub const Quat = @Vector(4, Real);
