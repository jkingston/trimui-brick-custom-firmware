// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const Motion = struct {
    from: i32 = 0,
    started_ms: i64 = 0,
    reduced: bool = @import("design.zig").motion.reduced,
    const duration_ms = @import("design.zig").motion.duration_ms;

    pub fn offset(self: Motion, now_ms: i64) i16 {
        const elapsed = std.math.clamp(now_ms - self.started_ms, 0, duration_ms);
        const remaining: i64 = duration_ms - elapsed;
        return switch (@import("design.zig").motion.easing) {
            .quadratic_out => @intCast(@divTrunc(@as(i64, self.from) * remaining * remaining, duration_ms * duration_ms)),
        };
    }

    pub fn retarget(self: *Motion, delta: i32, now_ms: i64) void {
        if (self.reduced) {
            self.from = 0;
            return;
        }
        self.from = std.math.clamp(@as(i32, self.offset(now_ms)) + delta * 1000, -2000, 2000);
        self.started_ms = now_ms;
    }

    pub fn active(self: Motion, now_ms: i64) bool {
        return self.from != 0 and now_ms - self.started_ms < duration_ms;
    }
};

test "shelf motion retargets without losing position and settles" {
    var motion = Motion{};
    motion.retarget(1, 100);
    try std.testing.expectEqual(@as(i16, 1000), motion.offset(100));
    const before = motion.offset(150);
    motion.retarget(-1, 150);
    try std.testing.expectEqual(before - 1000, motion.offset(150));
    try std.testing.expect(!motion.active(300));
    try std.testing.expectEqual(@as(i16, 0), motion.offset(300));
}

test "reduced motion settles immediately without scheduled frames" {
    var motion = Motion{ .reduced = true };
    motion.retarget(1, 100);
    try std.testing.expect(!motion.active(100));
    try std.testing.expectEqual(@as(i16, 0), motion.offset(100));
}
