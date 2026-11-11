// SPDX-License-Identifier: GPL-2.0-only
const ui = @import("ui_scene.zig");

/// Supplies a single semantic phase to every indeterminate activity indicator
/// in a rebuilt scene. The scene owns meaning and placement; the controller
/// owns cadence and reduced-motion behavior.
pub const Controller = struct {
    present: bool = false,
    started_ms: i64 = 0,
    reduced: bool = false,

    pub fn update(self: *Controller, tree: *const ui.Tree, now_ms: i64, reduced: bool) void {
        const present = tree.hasActivity();
        if (present and !self.present) self.started_ms = now_ms;
        self.present = present;
        self.reduced = reduced;
    }

    pub fn decorate(self: Controller, tree: *ui.Tree, now_ms: i64) void {
        if (!self.present) return;
        const elapsed = @max(0, now_ms - self.started_ms);
        tree.setActivityPhase(if (self.reduced) 0 else @intCast(@mod(elapsed, 900) * 1000 / 900), !self.reduced);
    }

    pub fn active(self: Controller) bool {
        return self.present and !self.reduced;
    }
};

test "activity cycles while present and becomes static with reduced motion" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .activity = .{ .bounds = .{ .x = 0, .y = 0, .width = 48, .height = 20 }, .color = theme.accent } });
    var controller = Controller{};
    controller.update(&tree, 100, false);
    controller.decorate(&tree, 550);
    try @import("std").testing.expectEqual(@as(u16, 500), tree.elements[0].activity.phase);
    try @import("std").testing.expect(controller.active());
    controller.update(&tree, 600, true);
    controller.decorate(&tree, 700);
    try @import("std").testing.expectEqual(@as(u16, 0), tree.elements[0].activity.phase);
    try @import("std").testing.expect(!tree.elements[0].activity.animated);
    try @import("std").testing.expect(!controller.active());
}
