// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const interaction = @import("interaction.zig");
const motion = @import("motion.zig");
const ui = @import("ui_scene.zig");

/// Keeps the focus indicator spatially continuous while views remain stateless.
/// A screen only declares the newly focused component; this controller tracks
/// the visible rail position and retargets it on rapid navigation.
pub const Controller = struct {
    id: ?interaction.Id = null,
    target_y: i32 = 0,
    position: motion.Scalar = motion.Scalar.init(0, .focus),

    pub fn update(self: *Controller, tree: *const ui.Tree, now_ms: i64, reduced: bool) void {
        const focus = tree.focus() orelse {
            self.id = null;
            return;
        };
        const y: i32 = focus.bounds.y;
        self.position.reduced = reduced;
        if (self.id == null) {
            self.id = focus.id;
            self.target_y = y;
            self.position = motion.Scalar.init(y, .focus);
            self.position.reduced = reduced;
        } else if (self.id.? != focus.id or self.target_y != y) {
            self.id = focus.id;
            self.target_y = y;
            self.position.retarget(y, now_ms);
        }
    }

    pub fn decorate(self: Controller, tree: *ui.Tree, now_ms: i64) void {
        const id = self.id orelse return;
        const offset = std.math.clamp(self.position.value(now_ms) - self.target_y, std.math.minInt(i16), std.math.maxInt(i16));
        _ = tree.setFocusOffset(id, @intCast(offset));
    }

    pub fn active(self: Controller, now_ms: i64) bool {
        return self.position.active(now_ms);
    }
};

test "focus rail retargets from its visible position" {
    const theme = @import("theme.zig").light;
    var first = ui.Tree{ .theme = theme, .background = theme.background };
    first.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.home, 0), .bounds = .{ .x = 0, .y = 100, .width = 200, .height = 80 }, .label = "One", .selected = true } });
    var second = ui.Tree{ .theme = theme, .background = theme.background };
    second.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.home, 1), .bounds = .{ .x = 0, .y = 300, .width = 200, .height = 80 }, .label = "Two", .selected = true } });
    var controller = Controller{};
    controller.update(&first, 0, false);
    controller.update(&second, 10, false);
    controller.decorate(&second, 10);
    try std.testing.expectEqual(@as(i16, -200), second.elements[0].menu_row.focus_offset_y);
    controller.decorate(&second, 60);
    const before = second.elements[0].menu_row.focus_offset_y;
    controller.update(&first, 60, false);
    controller.decorate(&first, 60);
    try std.testing.expectEqual(@as(i16, 200) + before, first.elements[0].menu_row.focus_offset_y);
    try std.testing.expect(controller.active(60));
}

test "reduced motion keeps focus state without scheduling movement" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .menu_row = .{ .bounds = .{ .x = 0, .y = 100, .width = 200, .height = 80 }, .label = "One", .selected = true } });
    var controller = Controller{};
    controller.update(&tree, 0, true);
    controller.decorate(&tree, 0);
    try std.testing.expect(!controller.active(0));
    try std.testing.expectEqual(@as(i16, 0), tree.elements[0].menu_row.focus_offset_y);
}
