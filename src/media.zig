// SPDX-License-Identifier: GPL-2.0-only

pub const Kind = enum { music, podcast, audiobook };
pub const Policy = struct {
    resume_position: bool,
    backward_seconds: u16,
    forward_seconds: u16,
    checkpoint_seconds: u16,
    completion_percent: u8,
    default_speed_x100: u16,
};

pub fn policy(kind: Kind) Policy {
    return switch (kind) {
        .music => .{ .resume_position = false, .backward_seconds = 5, .forward_seconds = 10, .checkpoint_seconds = 30, .completion_percent = 95, .default_speed_x100 = 100 },
        .podcast => .{ .resume_position = true, .backward_seconds = 15, .forward_seconds = 30, .checkpoint_seconds = 15, .completion_percent = 95, .default_speed_x100 = 100 },
        .audiobook => .{ .resume_position = true, .backward_seconds = 30, .forward_seconds = 30, .checkpoint_seconds = 15, .completion_percent = 98, .default_speed_x100 = 100 },
    };
}

pub fn completed(kind: Kind, position_ms: u64, duration_ms: u64) bool {
    if (duration_ms == 0) return false;
    return position_ms >= (duration_ms * policy(kind).completion_percent) / 100;
}

pub fn resumeAt(kind: Kind, saved_ms: u64, duration_ms: u64) u64 {
    if (!policy(kind).resume_position or completed(kind, saved_ms, duration_ms)) return 0;
    // Rewind speech slightly so a restored session starts with context.
    const context_ms: u64 = if (kind == .audiobook) 3000 else 1500;
    return saved_ms -| context_ms;
}

pub fn clampSpeed(speed_x100: u16) u16 {
    return @min(@max(speed_x100, 50), 300);
}

test "spoken media resumes with context but music starts at the track boundary" {
    const testing = @import("std").testing;
    try testing.expectEqual(@as(u64, 0), resumeAt(.music, 120_000, 240_000));
    try testing.expectEqual(@as(u64, 118_500), resumeAt(.podcast, 120_000, 240_000));
    try testing.expectEqual(@as(u64, 117_000), resumeAt(.audiobook, 120_000, 240_000));
}

test "completed spoken item does not resume at its tail" {
    const testing = @import("std").testing;
    try testing.expect(completed(.podcast, 96_000, 100_000));
    try testing.expectEqual(@as(u64, 0), resumeAt(.podcast, 96_000, 100_000));
    try testing.expectEqual(@as(u16, 300), clampSpeed(500));
}
