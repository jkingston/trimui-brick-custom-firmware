// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const design = @import("design.zig");

/// A reusable, interruptible scalar. Values are caller-defined fixed-point
/// units so layout code stays integer-only and deterministic.
pub const Scalar = struct {
    from: i32 = 0,
    target: i32 = 0,
    started_ms: i64 = 0,
    token: design.Motion = design.motion_tokens.content,
    reduced: bool = false,

    pub fn init(initial: i32, role: design.MotionRole) Scalar {
        return .{ .from = initial, .target = initial, .token = design.motion_tokens.get(role) };
    }

    pub fn value(self: Scalar, now_ms: i64) i32 {
        if (self.reduced or self.from == self.target) return self.target;
        const elapsed = std.math.clamp(now_ms - self.started_ms, 0, self.token.duration_ms);
        const progress: i64 = @divTrunc(elapsed * 65_536, self.token.duration_ms);
        const eased = ease(self.token.easing, progress);
        return self.from + @as(i32, @intCast(@divTrunc(@as(i64, self.target - self.from) * eased, 65_536)));
    }

    /// Retarget from the value visible now, never from a stale endpoint. This
    /// makes rapid reversals feel controlled instead of queued.
    pub fn retarget(self: *Scalar, target: i32, now_ms: i64) void {
        const current = self.value(now_ms);
        self.from = if (self.reduced) target else current;
        self.target = target;
        self.started_ms = now_ms;
    }

    pub fn active(self: Scalar, now_ms: i64) bool {
        return !self.reduced and self.from != self.target and now_ms - self.started_ms < self.token.duration_ms;
    }

    pub fn nextFrameMs(self: Scalar, now_ms: i64) ?i32 {
        if (!self.active(now_ms)) return null;
        return @intCast(self.token.frame_ms);
    }
};

fn ease(curve: design.Easing, progress: i64) i64 {
    const p = std.math.clamp(progress, 0, 65_536);
    return switch (curve) {
        .standard => p,
        .accelerate => @divTrunc(p * p, 65_536),
        .decelerate => 65_536 - @divTrunc((65_536 - p) * (65_536 - p), 65_536),
    };
}

/// Merge an animation deadline with service/input deadlines. The final zero
/// timeout paints the settled endpoint even when no other event arrives.
pub fn pollTimeout(active: bool, was_active: bool, other_ms: i32) i32 {
    if (active) {
        const frame: i32 = design.motion_tokens.content.frame_ms;
        return if (other_ms < 0) frame else @min(frame, other_ms);
    }
    if (was_active) return 0;
    return other_ms;
}

test "retargeting starts from the currently visible value" {
    var value = Scalar.init(0, .content);
    value.retarget(1000, 0);
    const visible = value.value(50);
    value.retarget(-1000, 50);
    try std.testing.expectEqual(visible, value.value(50));
    try std.testing.expect(value.active(50));
    try std.testing.expectEqual(@as(i32, -1000), value.value(500));
}

test "reduced motion preserves state changes without scheduling frames" {
    var value = Scalar.init(10, .enter);
    value.reduced = true;
    value.retarget(20, 0);
    try std.testing.expectEqual(@as(i32, 20), value.value(0));
    try std.testing.expect(value.nextFrameMs(0) == null);
}

test "semantic curves make exits direct and entrances settle" {
    var enter = Scalar.init(0, .enter);
    var exit = Scalar.init(0, .exit);
    enter.retarget(1000, 0);
    exit.retarget(1000, 0);
    try std.testing.expect(enter.value(60) > exit.value(60));
}

test "active motion always contributes a frame deadline" {
    try std.testing.expectEqual(@as(i32, 16), pollTimeout(true, false, -1));
    try std.testing.expectEqual(@as(i32, 5), pollTimeout(true, false, 5));
    try std.testing.expectEqual(@as(i32, 0), pollTimeout(false, true, 5000));
    try std.testing.expectEqual(@as(i32, 5000), pollTimeout(false, false, 5000));
}
