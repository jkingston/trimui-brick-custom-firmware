// SPDX-License-Identifier: GPL-2.0-only
pub const Scheduler = struct {
    dirty: bool = true,
    animation_deadline_ns: ?u64 = null,
    frames: u64 = 0,

    pub fn invalidate(self: *Scheduler, now_ns: u64, animate: bool) void {
        self.dirty = true;
        self.animation_deadline_ns = if (animate) now_ns + 140_000_000 else null;
    }

    pub fn shouldRender(self: *const Scheduler, now_ns: u64) bool {
        return self.dirty or if (self.animation_deadline_ns) |deadline| now_ns < deadline else false;
    }

    pub fn rendered(self: *Scheduler, now_ns: u64) void {
        self.frames += 1;
        self.dirty = false;
        if (self.animation_deadline_ns) |deadline| {
            if (now_ns >= deadline) self.animation_deadline_ns = null;
        }
    }

    pub fn nextWake(self: *const Scheduler, now_ns: u64) ?u64 {
        if (self.dirty) return now_ns;
        if (self.animation_deadline_ns) |deadline| {
            if (now_ns < deadline) return @min(deadline, now_ns + 16_666_667);
        }
        return null;
    }
};

test "static screen has no periodic wakeup" {
    const testing = @import("std").testing;
    var scheduler = Scheduler{};
    try testing.expect(scheduler.shouldRender(0));
    scheduler.rendered(0);
    try testing.expect(!scheduler.shouldRender(1));
    try testing.expectEqual(@as(?u64, null), scheduler.nextWake(1));
}

test "animation is bounded then returns to idle" {
    const testing = @import("std").testing;
    var scheduler = Scheduler{ .dirty = false };
    scheduler.invalidate(1_000, true);
    try testing.expect(scheduler.nextWake(1_000) != null);
    scheduler.rendered(140_001_000);
    try testing.expectEqual(@as(?u64, null), scheduler.nextWake(140_001_001));
}
