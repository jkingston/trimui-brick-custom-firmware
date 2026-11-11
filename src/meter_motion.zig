// SPDX-License-Identifier: GPL-2.0-only
const interaction = @import("interaction.zig");
const motion = @import("motion.zig");
const ui = @import("ui_scene.zig");

/// Smooths declarative meter values without making the view stateful. Repeated
/// adjustments retarget from the currently visible thumb position.
pub const Controller = struct {
    id: interaction.Id = .none,
    target: i32 = 0,
    value: motion.Scalar = motion.Scalar.init(0, .content),

    pub fn update(self: *Controller, tree: *const ui.Tree, id: interaction.Id, now_ms: i64, reduced: bool) void {
        const target: i32 = tree.meterValue(id) orelse {
            self.id = .none;
            return;
        };
        if (self.id != id) {
            self.id = id;
            self.target = target;
            self.value = motion.Scalar.init(target, .content);
            self.value.reduced = reduced;
            return;
        }
        self.value.reduced = reduced;
        if (self.target != target) {
            self.target = target;
            self.value.retarget(target, now_ms);
        }
    }

    pub fn decorate(self: Controller, tree: *ui.Tree, now_ms: i64) void {
        if (self.id == .none) return;
        _ = tree.setMeterValue(self.id, @intCast(@max(0, self.value.value(now_ms))));
    }

    pub fn active(self: Controller, now_ms: i64) bool {
        return self.id != .none and self.value.active(now_ms);
    }
};

test "meter retargets from its visible value during rapid adjustment" {
    const theme = @import("theme.zig").light;
    const id = interaction.Id.scoped(.brightness_meter, 0);
    var first = ui.Tree{ .theme = theme, .background = theme.background };
    first.add(.{ .meter = .{ .id = id, .bounds = .{ .x = 0, .y = 0, .width = 100, .height = 40 }, .value = 200, .track = theme.surface, .fill = theme.text, .thumb = theme.accent } });
    var second = first;
    second.elements[0].meter.value = 800;
    var controller = Controller{};
    controller.update(&first, id, 0, false);
    controller.update(&second, id, 10, false);
    var visible = second;
    controller.decorate(&visible, 60);
    const before = visible.elements[0].meter.value;
    var third = second;
    third.elements[0].meter.value = 400;
    controller.update(&third, id, 60, false);
    controller.decorate(&third, 60);
    try @import("std").testing.expectEqual(before, third.elements[0].meter.value);
}

test "reduced motion resolves meter value immediately" {
    const theme = @import("theme.zig").light;
    const id = interaction.Id.scoped(.brightness_meter, 0);
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .meter = .{ .id = id, .bounds = .{ .x = 0, .y = 0, .width = 100, .height = 40 }, .value = 200, .track = theme.surface, .fill = theme.text, .thumb = theme.accent } });
    var controller = Controller{};
    controller.update(&tree, id, 0, true);
    tree.elements[0].meter.value = 900;
    controller.update(&tree, id, 10, true);
    controller.decorate(&tree, 10);
    try @import("std").testing.expectEqual(@as(u16, 900), tree.elements[0].meter.value);
    try @import("std").testing.expect(!controller.active(10));
}
