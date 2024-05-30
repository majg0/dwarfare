const std = @import("std");

const Timer = @This();

step_duration_ns: u64,
prev_start_time: std.time.Instant,
duration_budget_ns: u64,
frame_index: u64,

pub fn init(self: *Timer, fps: u64) error{Unsupported}!void {
    self.* = Timer{
        .step_duration_ns = std.time.ns_per_s / fps,
        .prev_start_time = try std.time.Instant.now(),
        .duration_budget_ns = 0,
        .frame_index = 0,
    };
}

pub fn accumulate_duration(self: *Timer) error{Unsupported}!void {
    const start_time = try std.time.Instant.now();
    self.duration_budget_ns += start_time.since(self.prev_start_time);
    self.prev_start_time = start_time;
}

pub fn canTick(self: *const Timer) bool {
    return self.duration_budget_ns >= self.step_duration_ns;
}

pub fn tick(self: *Timer) void {
    self.duration_budget_ns -= self.step_duration_ns;
    self.frame_index += 1;
}

pub fn interpolate_frames(self: *const Timer) f64 {
    return @as(f64, @floatFromInt(self.duration_budget_ns)) /
        @as(f64, @floatFromInt(self.step_duration_ns));
}
