// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const motion = @import("motion.zig");
const ui = @import("ui_scene.zig");

pub const Direction = enum { forward, back };

pub const Frame = struct {
    base: *const ui.Tree,
    overlay: *const ui.Tree,
    offset_x: i16,
};

/// Retains both declarative scenes for an immediate, interruption-safe settle.
/// The destination is already legible on the first frame; a small mirrored
/// offset preserves hierarchy without turning navigation into a page wipe.
pub const Controller = struct {
    from: ui.Tree = .{ .background = @import("theme.zig").light.background },
    to: ui.Tree = .{ .background = @import("theme.zig").light.background },
    direction: Direction = .forward,
    progress: motion.Scalar = motion.Scalar.init(1000, .enter),
    running: bool = false,

    pub fn begin(self: *Controller, from: *const ui.Tree, to: *const ui.Tree, direction: Direction, now_ms: i64, reduced: bool) void {
        self.from = from.*;
        self.to = to.*;
        self.direction = direction;
        self.progress = motion.Scalar.init(0, if (direction == .forward) .enter else .exit);
        self.progress.reduced = reduced;
        self.progress.retarget(1000, now_ms);
        self.running = !reduced;
    }

    pub fn cancel(self: *Controller) void {
        self.running = false;
    }

    pub fn active(self: *const Controller, now_ms: i64) bool {
        return self.running and self.progress.active(now_ms);
    }

    pub fn frame(self: *const Controller, now_ms: i64) Frame {
        const amount = std.math.clamp(self.progress.value(now_ms), 0, 1000);
        const remaining: i16 = @intCast(@divTrunc(@as(i32, settle_distance) * (1000 - amount), 1000));
        return .{
            .base = &self.from,
            .overlay = &self.to,
            .offset_x = switch (self.direction) {
                .forward => remaining,
                .back => -remaining,
            },
        };
    }
};

/// Less than one margin: direction is felt, while the destination remains the
/// dominant frame from the instant the action is accepted.
pub const settle_distance: i16 = 24;

test "forward navigation settles the complete destination from the right" {
    const theme = @import("theme.zig").light;
    var from = ui.Tree{ .theme = theme, .background = theme.background };
    from.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 200, .width = 968, .height = 88 }, .label = "Settings", .selected = true } });
    var to = ui.Tree{ .theme = theme, .background = theme.background };
    to.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 138, .width = 968, .height = 96 }, .label = "Brightness", .selected = true } });
    var transition = Controller{};
    transition.begin(&from, &to, .forward, 0, false);
    try std.testing.expectEqual(settle_distance, transition.frame(0).offset_x);
    try std.testing.expectEqual(@as(i16, 0), transition.frame(1000).offset_x);
    try std.testing.expectEqual(&transition.from, transition.frame(0).base);
    try std.testing.expectEqual(&transition.to, transition.frame(0).overlay);
}

test "back navigation mirrors the destination settle" {
    const theme = @import("theme.zig").light;
    var from = ui.Tree{ .theme = theme, .background = theme.background };
    from.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 138, .width = 968, .height = 96 }, .label = "Brightness", .selected = true } });
    var to = ui.Tree{ .theme = theme, .background = theme.background };
    to.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 300, .width = 968, .height = 96 }, .label = "Settings", .selected = true } });
    var transition = Controller{};
    transition.begin(&from, &to, .back, 0, false);
    try std.testing.expectEqual(-settle_distance, transition.frame(0).offset_x);
    try std.testing.expectEqual(@as(i16, 0), transition.frame(1000).offset_x);
    try std.testing.expectEqual(&transition.from, transition.frame(0).base);
    try std.testing.expectEqual(&transition.to, transition.frame(0).overlay);
}

test "reduced motion resolves without scheduled transition frames" {
    const theme = @import("theme.zig").light;
    const from = ui.Tree{ .theme = theme, .background = theme.background };
    const to = ui.Tree{ .theme = theme, .background = theme.background };
    var transition = Controller{};
    transition.begin(&from, &to, .forward, 0, true);
    try std.testing.expect(!transition.active(0));
    try std.testing.expectEqual(@as(i16, 0), transition.frame(0).offset_x);
}

test "new input can finish navigation without queueing" {
    const theme = @import("theme.zig").light;
    const from = ui.Tree{ .theme = theme, .background = theme.background };
    const to = ui.Tree{ .theme = theme, .background = theme.background };
    var transition = Controller{};
    transition.begin(&from, &to, .forward, 0, false);
    try std.testing.expect(transition.active(20));
    transition.cancel();
    try std.testing.expect(!transition.active(20));
}
