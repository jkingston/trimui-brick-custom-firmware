// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const Pacer = struct {
    due_us: ?i64 = null,
    target_us: i64 = 0,
    budget_us: i64 = 4000,
    recent_work_us: [16]i64 = @splat(0),
    next_sample: usize = 0,

    pub fn request(self: *Pacer, now_us: i64, vblank_us: i64, period_us: i64) void {
        if (self.due_us != null) return;
        const elapsed = @max(0, now_us - vblank_us);
        const next = vblank_us + (@divFloor(elapsed, period_us) + 1) * period_us;
        self.target_us = next;
        self.due_us = @max(now_us, next - self.budget_us);
    }

    pub fn immediate(self: *Pacer, now_us: i64) void {
        self.target_us = 0;
        self.due_us = now_us;
    }

    pub fn ready(self: Pacer, now_us: i64) bool {
        return if (self.due_us) |due| now_us >= due else false;
    }

    pub fn waitUs(self: Pacer, now_us: i64, other_ms: i32) i64 {
        const frame_wait = @max(0, self.due_us.? - now_us);
        return if (other_ms < 0) frame_wait else @min(frame_wait, @as(i64, other_ms) * 1000);
    }

    pub fn painted(self: *Pacer, work_us: i64) void {
        self.due_us = null;
        self.target_us = 0;
        self.recent_work_us[self.next_sample] = work_us;
        self.next_sample = (self.next_sample + 1) % self.recent_work_us.len;
        self.budget_us = @max(4000, std.mem.max(i64, &self.recent_work_us) + 1000);
    }
};

test "frame requests coalesce without postponing their deadline" {
    var pacer = Pacer{};
    try std.testing.expect(!pacer.ready(0));
    pacer.request(1000, 0, 16667);
    try std.testing.expectEqual(@as(?i64, 12667), pacer.due_us);
    pacer.request(9000, 0, 16667);
    try std.testing.expectEqual(@as(?i64, 12667), pacer.due_us);
    try std.testing.expectEqual(@as(i64, 3667), pacer.waitUs(9000, -1));
    try std.testing.expectEqual(@as(i64, 2000), pacer.waitUs(9000, 2));
    try std.testing.expect(!pacer.ready(12666));
    try std.testing.expect(pacer.ready(12667));
    pacer.painted(2000);
    try std.testing.expect(!pacer.ready(20000));
    pacer.request(30000, 0, 16667);
    try std.testing.expectEqual(@as(?i64, 30000), pacer.due_us);
}

test "plane-only presentation bypasses a pending repaint deadline" {
    var pacer = Pacer{};
    pacer.request(1000, 0, 16667);
    pacer.immediate(4000);
    try std.testing.expectEqual(@as(?i64, 4000), pacer.due_us);
    try std.testing.expect(pacer.ready(4000));
}

test "cold frames expand the margin and long idle gaps preserve the phase" {
    var pacer = Pacer{};
    pacer.painted(12000);
    try std.testing.expectEqual(@as(i64, 13000), pacer.budget_us);
    pacer.request(1666701000, 0, 16667);
    try std.testing.expectEqual(@as(?i64, 1666703667), pacer.due_us);
    pacer.painted(2000);
    try std.testing.expectEqual(@as(i64, 13000), pacer.budget_us);
    pacer.painted(20000);
    pacer.request(1000, 0, 16667);
    try std.testing.expectEqual(@as(?i64, 1000), pacer.due_us);
}

test "occasional expensive animation frames retain their allowance for sixteen frames" {
    var pacer = Pacer{};
    pacer.painted(6000);
    for (0..15) |_| {
        pacer.painted(2000);
        try std.testing.expectEqual(@as(i64, 7000), pacer.budget_us);
    }
    pacer.painted(2000);
    try std.testing.expectEqual(@as(i64, 4000), pacer.budget_us);
}

test "recurring animation work remains budgeted across a twelve-frame cycle" {
    var pacer = Pacer{};
    for (0..120) |frame| {
        pacer.painted(if (frame % 12 == 0) 5500 else 3500);
        try std.testing.expectEqual(@as(i64, 6500), pacer.budget_us);
    }
}

test "startup work does not suppress pacing for hundreds of warm frames" {
    var pacer = Pacer{};
    pacer.painted(100000);
    for (0..30) |_| pacer.painted(2000);
    try std.testing.expectEqual(@as(i64, 4000), pacer.budget_us);
}

test "input arriving after the deadline is not deferred another refresh" {
    var pacer = Pacer{};
    pacer.painted(2000);
    pacer.request(32000, 16667, 16667);
    try std.testing.expectEqual(@as(?i64, 32000), pacer.due_us);
    pacer.request(35000, 33334, 16667);
    try std.testing.expectEqual(@as(?i64, 32000), pacer.due_us);
}

test "continuous animation targets every refresh without a second frame delay" {
    var pacer = Pacer{};
    const period = 16667;
    for (0..120) |index| {
        const vblank: i64 = @as(i64, @intCast(index)) * period;
        pacer.request(vblank + 200, vblank, period);
        const due = pacer.due_us.?;
        try std.testing.expectEqual(vblank + period - 4000, due);
        try std.testing.expect(due + 2000 < vblank + period);
        pacer.painted(2000);
    }
}

test "refresh targets survive coalescing and clear when painted" {
    var pacer = Pacer{};
    pacer.painted(150);
    try std.testing.expectEqual(@as(i64, 4000), pacer.budget_us);
    pacer.request(1000, 0, 16667);
    try std.testing.expectEqual(@as(?i64, 12667), pacer.due_us);
    try std.testing.expectEqual(@as(i64, 16667), pacer.target_us);
    pacer.request(14000, 0, 16667);
    try std.testing.expectEqual(@as(?i64, 12667), pacer.due_us);
    try std.testing.expectEqual(@as(i64, 16667), pacer.target_us);
    pacer.request(18000, 16667, 16667);
    try std.testing.expectEqual(@as(i64, 16667), pacer.target_us);
    try std.testing.expect(pacer.ready(18000));
    pacer.painted(3500);
    try std.testing.expectEqual(@as(i64, 0), pacer.target_us);
    try std.testing.expectEqual(@as(i64, 4500), pacer.budget_us);
}
