// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const interaction = @import("interaction.zig");
const input = @import("input.zig");
const motion = @import("motion.zig");
const ui = @import("ui_scene.zig");

/// Keeps the focus indicator spatially continuous while views remain stateless.
/// A screen only declares the newly focused component; this controller tracks
/// the visible focus-plate position and retargets it on rapid navigation.
pub const Controller = struct {
    id: ?interaction.Id = null,
    target_x: i32 = 0,
    target_y: i32 = 0,
    target_width: i32 = 0,
    target_height: i32 = 0,
    position_x: motion.Scalar = motion.Scalar.init(0, .focus),
    position_y: motion.Scalar = motion.Scalar.init(0, .focus),
    width: motion.Scalar = motion.Scalar.init(0, .focus),
    height: motion.Scalar = motion.Scalar.init(0, .focus),
    boundary_x: motion.Scalar = motion.Scalar.init(0, .press),
    boundary_y: motion.Scalar = motion.Scalar.init(0, .press),
    boundary_until_ms: i64 = 0,

    pub fn update(self: *Controller, tree: *const ui.Tree, now_ms: i64, reduced: bool) void {
        const focus = tree.focus() orelse {
            self.id = null;
            return;
        };
        const x: i32 = focus.bounds.x;
        const y: i32 = focus.bounds.y;
        const width: i32 = focus.bounds.width;
        const height: i32 = focus.bounds.height;
        self.position_x.reduced = reduced;
        self.position_y.reduced = reduced;
        self.width.reduced = reduced;
        self.height.reduced = reduced;
        if (self.id == null) {
            self.id = focus.id;
            self.target_x = x;
            self.target_y = y;
            self.target_width = width;
            self.target_height = height;
            self.position_x = motion.Scalar.init(x, .focus);
            self.position_y = motion.Scalar.init(y, .focus);
            self.width = motion.Scalar.init(width, .focus);
            self.height = motion.Scalar.init(height, .focus);
            self.position_x.reduced = reduced;
            self.position_y.reduced = reduced;
            self.width.reduced = reduced;
            self.height.reduced = reduced;
        } else if (self.id.? != focus.id or self.target_x != x or self.target_y != y or self.target_width != width or self.target_height != height) {
            self.id = focus.id;
            self.target_x = x;
            self.target_y = y;
            self.target_width = width;
            self.target_height = height;
            self.position_x.retarget(x, now_ms);
            self.position_y.retarget(y, now_ms);
            self.width.retarget(width, now_ms);
            self.height.retarget(height, now_ms);
        }
    }

    pub fn decorate(self: Controller, tree: *ui.Tree, now_ms: i64) void {
        const id = self.id orelse return;
        if (now_ms < self.boundary_until_ms) _ = tree.setInteraction(id, .boundary);
        const offset_x = std.math.clamp(self.position_x.value(now_ms) - self.target_x + self.boundary_x.value(now_ms), std.math.minInt(i16), std.math.maxInt(i16));
        const offset_y = std.math.clamp(self.position_y.value(now_ms) - self.target_y + self.boundary_y.value(now_ms), std.math.minInt(i16), std.math.maxInt(i16));
        _ = tree.setFocusOffset(id, @intCast(offset_x), @intCast(offset_y));
        const width_delta = std.math.clamp(self.width.value(now_ms) - self.target_width, std.math.minInt(i16), std.math.maxInt(i16));
        const height_delta = std.math.clamp(self.height.value(now_ms) - self.target_height, std.math.minInt(i16), std.math.maxInt(i16));
        _ = tree.setFocusSizeOffset(id, @intCast(width_delta), @intCast(height_delta));
    }

    pub fn active(self: Controller, now_ms: i64) bool {
        return self.position_x.active(now_ms) or self.position_y.active(now_ms) or self.width.active(now_ms) or self.height.active(now_ms) or
            self.boundary_x.active(now_ms) or self.boundary_y.active(now_ms) or
            now_ms < self.boundary_until_ms;
    }

    /// A boundary is an acknowledged result, not ignored input. Normal motion
    /// nudges toward the attempted direction; reduced motion keeps only the
    /// stronger perimeter pulse.
    pub fn boundary(self: *Controller, action: input.Action, now_ms: i64, reduced: bool) bool {
        const impulse: i32 = switch (action) {
            .up, .left => -10,
            .down, .right => 10,
            else => return false,
        };
        if (self.id == null) return false;
        var value = motion.Scalar.init(if (reduced) 0 else impulse, .press);
        value.reduced = reduced;
        value.retarget(0, now_ms);
        switch (action) {
            .left, .right => self.boundary_x = value,
            .up, .down => self.boundary_y = value,
            else => unreachable,
        }
        self.boundary_until_ms = now_ms + @import("design.zig").motion_tokens.press.duration_ms;
        return true;
    }
};

test "focus plate retargets from its visible position" {
    const theme = @import("theme.zig").light;
    var first = ui.Tree{ .theme = theme, .background = theme.background };
    first.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.foyer, 0), .bounds = .{ .x = 0, .y = 100, .width = 200, .height = 80 }, .label = "One", .selected = true } });
    var second = ui.Tree{ .theme = theme, .background = theme.background };
    second.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.foyer, 1), .bounds = .{ .x = 0, .y = 300, .width = 200, .height = 80 }, .label = "Two", .selected = true } });
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

test "focus plate preserves horizontal continuity for grids" {
    const theme = @import("theme.zig").light;
    var first = ui.Tree{ .theme = theme, .background = theme.background };
    first.add(.{ .focus_frame = .{ .id = interaction.Id.scoped(.library, 0), .state = .focused, .bounds = .{ .x = 48, .y = 100, .width = 200, .height = 80 } } });
    var second = ui.Tree{ .theme = theme, .background = theme.background };
    second.add(.{ .focus_frame = .{ .id = interaction.Id.scoped(.library, 1), .state = .focused, .bounds = .{ .x = 364, .y = 100, .width = 200, .height = 80 } } });
    var controller = Controller{};
    controller.update(&first, 0, false);
    controller.update(&second, 10, false);
    controller.decorate(&second, 10);
    try std.testing.expectEqual(@as(i16, -316), second.elements[0].focus_frame.focus_offset_x);
    try std.testing.expectEqual(@as(i16, 0), second.elements[0].focus_frame.focus_offset_y);
}

test "focus plate morphs between differently sized action cards" {
    const theme = @import("theme.zig").light;
    var first = ui.Tree{ .theme = theme, .background = theme.background };
    first.add(.{ .action_card = .{ .id = interaction.Id.scoped(.foyer, 0), .state = .focused, .bounds = .{ .x = 28, .y = 142, .width = 614, .height = 468 }, .eyebrow = "Library", .label = "Games" } });
    var second = ui.Tree{ .theme = theme, .background = theme.background };
    second.add(.{ .action_card = .{ .id = interaction.Id.scoped(.foyer, 1), .state = .focused, .bounds = .{ .x = 670, .y = 142, .width = 326, .height = 220 }, .eyebrow = "Device", .label = "Settings" } });
    var controller = Controller{};
    controller.update(&first, 0, false);
    controller.update(&second, 10, false);
    controller.decorate(&second, 10);
    try std.testing.expectEqual(@as(i16, -642), second.elements[0].action_card.focus_offset_x);
    try std.testing.expectEqual(@as(i16, 288), second.elements[0].action_card.focus_width_delta);
    try std.testing.expectEqual(@as(i16, 248), second.elements[0].action_card.focus_height_delta);
    try std.testing.expectEqual(@as(u16, 614), second.elements[0].action_card.displayedBounds().width);
    try std.testing.expectEqual(@as(u16, 468), second.elements[0].action_card.displayedBounds().height);
}

test "keyboard focus retargets between stable key identities" {
    const theme = @import("theme.zig").light;
    var first = ui.Tree{ .theme = theme, .background = theme.background };
    first.add(.{ .keyboard = .{ .bounds = .{ .x = 48, .y = 260, .width = 928, .height = 328 }, .selected = 10 } });
    var second = ui.Tree{ .theme = theme, .background = theme.background };
    second.add(.{ .keyboard = .{ .bounds = .{ .x = 48, .y = 260, .width = 928, .height = 328 }, .selected = 11 } });
    var controller = Controller{};
    controller.update(&first, 0, false);
    controller.update(&second, 10, false);
    controller.decorate(&second, 10);
    try std.testing.expectEqual(@as(i16, -93), second.elements[0].keyboard.focus_offset_x);
    try std.testing.expect(controller.active(10));
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

test "boundary response nudges normally and pulses without motion when reduced" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .menu_row = .{ .bounds = .{ .x = 20, .y = 100, .width = 200, .height = 80 }, .label = "One", .selected = true } });
    var controller = Controller{};
    controller.update(&tree, 0, false);
    try std.testing.expect(controller.boundary(.up, 10, false));
    controller.decorate(&tree, 10);
    try std.testing.expectEqual(interaction.State.boundary, tree.elements[0].menu_row.state);
    try std.testing.expectEqual(@as(i16, -10), tree.elements[0].menu_row.focus_offset_y);

    tree = ui.Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .menu_row = .{ .bounds = .{ .x = 20, .y = 100, .width = 200, .height = 80 }, .label = "One", .selected = true } });
    try std.testing.expect(controller.boundary(.up, 100, true));
    controller.decorate(&tree, 100);
    try std.testing.expectEqual(interaction.State.boundary, tree.elements[0].menu_row.state);
    try std.testing.expectEqual(@as(i16, 0), tree.elements[0].menu_row.focus_offset_y);
}
