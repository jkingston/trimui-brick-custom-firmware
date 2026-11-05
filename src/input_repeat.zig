// SPDX-License-Identifier: GPL-2.0-only

const input = @import("input.zig");

pub const initial_delay_ms: i64 = 325;

pub const Controller = struct {
    held: ?input.Action = null,
    next_ms: i64 = 0,
    repeats: u8 = 0,

    pub fn press(self: *Controller, action: input.Action, now_ms: i64) void {
        self.held = action;
        self.next_ms = now_ms + initial_delay_ms;
        self.repeats = 0;
    }

    pub fn release(self: *Controller, action: input.Action) void {
        if (self.held == action) self.* = .{};
    }

    pub fn reset(self: *Controller) void {
        self.* = .{};
    }

    pub fn timeout(self: *const Controller, now_ms: i64) i32 {
        if (self.held == null) return -1;
        const remaining = self.next_ms - now_ms;
        return @intCast(@max(@as(i64, 0), @min(remaining, std.math.maxInt(i32))));
    }

    pub fn due(self: *Controller, now_ms: i64) ?input.Action {
        const action = self.held orelse return null;
        if (now_ms < self.next_ms) return null;
        self.repeats +|= 1;
        self.next_ms = now_ms + period(self.repeats);
        return action;
    }

    fn period(repeats: u8) i64 {
        if (repeats < 5) return 125;
        if (repeats < 14) return 90;
        return 70;
    }
};

const std = @import("std");

test "repeat waits, accelerates, and stops on release" {
    var repeat: Controller = .{};
    repeat.press(.down, 1000);
    try std.testing.expectEqual(@as(i32, 325), repeat.timeout(1000));
    try std.testing.expect(repeat.due(1324) == null);
    try std.testing.expectEqual(input.Action.down, repeat.due(1325).?);
    try std.testing.expectEqual(@as(i32, 125), repeat.timeout(1325));
    for (0..4) |_| _ = repeat.due(repeat.next_ms);
    try std.testing.expectEqual(@as(i32, 90), repeat.timeout(repeat.next_ms - 90));
    for (0..9) |_| _ = repeat.due(repeat.next_ms);
    try std.testing.expectEqual(@as(i32, 70), repeat.timeout(repeat.next_ms - 70));
    repeat.release(.down);
    try std.testing.expectEqual(@as(i32, -1), repeat.timeout(5000));
}

test "a different direction replaces the held direction" {
    var repeat: Controller = .{};
    repeat.press(.down, 0);
    repeat.press(.left, 100);
    repeat.release(.down);
    try std.testing.expectEqual(input.Action.left, repeat.due(425).?);
}
