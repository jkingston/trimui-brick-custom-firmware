// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const Sample = struct { events: usize, oldest_to_flip_us: i64, newest_to_flip_us: i64, dispatch_us: i64, collection_us: i64 };
pub const Pending = struct {
    count: usize = 0,
    oldest_us: i64 = 0,
    newest_us: i64 = 0,
    collection_us: i64 = 0,

    pub fn recordAt(self: *Pending, event_us: i64, collected_us: i64) void {
        if (event_us <= 0 or collected_us < event_us) return;
        self.record(event_us);
        self.collection_us = @max(self.collection_us, collected_us - event_us);
    }

    pub fn record(self: *Pending, event_us: i64) void {
        if (event_us <= 0) return;
        self.oldest_us = if (self.count == 0) event_us else @min(self.oldest_us, event_us);
        self.newest_us = @max(self.newest_us, event_us);
        self.count += 1;
    }

    pub fn finish(self: *Pending, render_started_us: i64, flip_us: i64) ?Sample {
        defer self.* = .{};
        if (self.count == 0 or render_started_us < self.newest_us or flip_us < render_started_us) return null;
        return .{ .events = self.count, .oldest_to_flip_us = flip_us - self.oldest_us, .newest_to_flip_us = flip_us - self.newest_us, .dispatch_us = render_started_us - self.newest_us, .collection_us = self.collection_us };
    }
};

test "latency records coalesced events without reusing a previous flip" {
    var pending = Pending{};
    pending.recordAt(1000, 1200);
    pending.record(1500);
    const sample = pending.finish(1600, 2500).?;
    try std.testing.expectEqual(@as(usize, 2), sample.events);
    try std.testing.expectEqual(@as(i64, 1500), sample.oldest_to_flip_us);
    try std.testing.expectEqual(@as(i64, 1000), sample.newest_to_flip_us);
    try std.testing.expectEqual(@as(i64, 100), sample.dispatch_us);
    try std.testing.expectEqual(@as(i64, 200), sample.collection_us);
    try std.testing.expect(pending.finish(2600, 3000) == null);
    pending.record(3500);
    try std.testing.expect(pending.finish(3600, 3000) == null);
    try std.testing.expectEqual(@as(usize, 0), pending.count);
}

test "input collected during a pending flip belongs to the next frame" {
    var pending = Pending{};
    pending.record(1000);
    var submitted = pending;
    pending = .{};
    pending.record(2000);
    pending.record(3000);
    const first = submitted.finish(1500, 4000).?;
    try std.testing.expectEqual(@as(usize, 1), first.events);
    try std.testing.expectEqual(@as(i64, 3000), first.newest_to_flip_us);
    const second = pending.finish(4500, 5000).?;
    try std.testing.expectEqual(@as(usize, 2), second.events);
    try std.testing.expectEqual(@as(i64, 2000), second.newest_to_flip_us);
}
