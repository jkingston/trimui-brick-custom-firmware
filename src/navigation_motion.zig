// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const design = @import("design.zig");
const motion = @import("motion.zig");
const ui = @import("ui_scene.zig");

pub const Direction = enum { forward, back };

pub const Frame = struct {
    base: *const ui.Tree,
    overlay: *const ui.Tree,
    clip: ui.Rect,
};

/// Retains both declarative scenes for a connected, interruption-safe reveal.
/// Forward expands the destination from the activating control; back exposes
/// the restored parent while the departing page collapses into that control.
pub const Controller = struct {
    from: ui.Tree = .{ .background = @import("theme.zig").light.background },
    to: ui.Tree = .{ .background = @import("theme.zig").light.background },
    direction: Direction = .forward,
    anchor: ui.Rect = .{ .x = design.geometry.width / 2, .y = design.geometry.height / 2, .width = 1, .height = 1 },
    progress: motion.Scalar = motion.Scalar.init(1000, .enter),
    running: bool = false,

    pub fn begin(self: *Controller, from: *const ui.Tree, to: *const ui.Tree, direction: Direction, now_ms: i64, reduced: bool) void {
        self.from = from.*;
        self.to = to.*;
        self.direction = direction;
        self.anchor = switch (direction) {
            .forward => if (from.focus()) |focus| focus.bounds else fallbackAnchor(),
            .back => if (to.focus()) |focus| focus.bounds else fallbackAnchor(),
        };
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
        return switch (self.direction) {
            .forward => .{ .base = &self.from, .overlay = &self.to, .clip = interpolate(self.anchor, fullScreen(), amount) },
            .back => .{ .base = &self.to, .overlay = &self.from, .clip = interpolate(fullScreen(), self.anchor, amount) },
        };
    }
};

fn fullScreen() ui.Rect {
    return .{ .x = 0, .y = 0, .width = design.geometry.width, .height = design.geometry.height };
}

fn fallbackAnchor() ui.Rect {
    return .{ .x = design.geometry.width / 2 - 1, .y = design.geometry.height / 2 - 1, .width = 2, .height = 2 };
}

fn interpolate(from: ui.Rect, to: ui.Rect, amount: i32) ui.Rect {
    return .{
        .x = lerp(from.x, to.x, amount),
        .y = lerp(from.y, to.y, amount),
        .width = @max(1, lerp(from.width, to.width, amount)),
        .height = @max(1, lerp(from.height, to.height, amount)),
    };
}

fn lerp(from: u16, to: u16, amount: i32) u16 {
    return @intCast(@as(i32, from) + @divTrunc((@as(i32, to) - from) * amount, 1000));
}

test "forward navigation expands from the activating focus" {
    const theme = @import("theme.zig").light;
    var from = ui.Tree{ .theme = theme, .background = theme.background };
    from.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 200, .width = 968, .height = 88 }, .label = "Settings", .selected = true } });
    var to = ui.Tree{ .theme = theme, .background = theme.background };
    to.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 138, .width = 968, .height = 96 }, .label = "Brightness", .selected = true } });
    var transition = Controller{};
    transition.begin(&from, &to, .forward, 0, false);
    try std.testing.expectEqual(from.focus().?.bounds, transition.frame(0).clip);
    try std.testing.expectEqual(fullScreen(), transition.frame(1000).clip);
}

test "back navigation collapses into restored parent focus" {
    const theme = @import("theme.zig").light;
    var from = ui.Tree{ .theme = theme, .background = theme.background };
    from.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 138, .width = 968, .height = 96 }, .label = "Brightness", .selected = true } });
    var to = ui.Tree{ .theme = theme, .background = theme.background };
    to.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 300, .width = 968, .height = 96 }, .label = "Settings", .selected = true } });
    var transition = Controller{};
    transition.begin(&from, &to, .back, 0, false);
    try std.testing.expectEqual(fullScreen(), transition.frame(0).clip);
    try std.testing.expectEqual(to.focus().?.bounds, transition.frame(1000).clip);
}

test "reduced motion resolves without scheduled transition frames" {
    const theme = @import("theme.zig").light;
    const from = ui.Tree{ .theme = theme, .background = theme.background };
    const to = ui.Tree{ .theme = theme, .background = theme.background };
    var transition = Controller{};
    transition.begin(&from, &to, .forward, 0, true);
    try std.testing.expect(!transition.active(0));
    try std.testing.expectEqual(fullScreen(), transition.frame(0).clip);
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
