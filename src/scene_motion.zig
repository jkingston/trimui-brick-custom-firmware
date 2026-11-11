// SPDX-License-Identifier: GPL-2.0-only
//! Shared runtime for motion that decorates declarative scenes. Feature loops
//! rebuild content; this controller owns continuity between those rebuilds.
const activity_motion = @import("activity_motion.zig");
const focus_motion = @import("focus_motion.zig");
const interaction = @import("interaction.zig");
const layout_motion = @import("layout_motion.zig");
const meter_motion = @import("meter_motion.zig");
const navigation_motion = @import("navigation_motion.zig");
const ui = @import("ui_scene.zig");

pub const Controller = struct {
    focus: focus_motion.Controller = .{},
    meter: meter_motion.Controller = .{},
    activity: activity_motion.Controller = .{},
    navigation: navigation_motion.Controller = .{},
    layout: layout_motion.Controller = .{},

    /// Initialize fields independently. A single aggregate default would embed
    /// a device-sized constant containing retained scene buffers in the binary.
    pub fn reset(self: *Controller) void {
        self.focus = .{};
        self.meter = .{};
        self.activity = .{};
        self.navigation = .{};
        self.layout = .{};
    }

    pub fn decorate(self: *Controller, tree: *ui.Tree, now_ms: i64, reduced: bool, meter_id: ?interaction.Id) void {
        self.focus.update(tree, now_ms, reduced);
        self.focus.decorate(tree, now_ms);
        if (meter_id) |id| {
            self.meter.update(tree, id, now_ms, reduced);
            self.meter.decorate(tree, now_ms);
        }
        self.activity.update(tree, now_ms, reduced);
        self.activity.decorate(tree, now_ms);
    }

    pub fn active(self: *const Controller, now_ms: i64) bool {
        return self.focus.active(now_ms) or self.meter.active(now_ms) or self.activity.active() or self.navigation.active(now_ms) or self.layout.active(now_ms);
    }

    pub fn beginNavigation(self: *Controller, source: *const ui.Tree, destination: *ui.Tree, direction: navigation_motion.Direction, now_ms: i64, reduced: bool, meter_id: ?interaction.Id) void {
        self.focus = .{};
        self.decorate(destination, now_ms, reduced, meter_id);
        self.navigation.begin(source, destination, direction, now_ms, reduced);
    }

    /// Routine shell destinations cut after the source control has completed
    /// its press acknowledgement. Reset focus continuity so unrelated pages do
    /// not appear to morph into one another.
    pub fn cutTo(self: *Controller, destination: *ui.Tree, now_ms: i64, reduced: bool, meter_id: ?interaction.Id) void {
        self.navigation.cancel();
        self.layout.cancel();
        self.focus = .{};
        self.decorate(destination, now_ms, reduced, meter_id);
    }

    pub fn cancelNavigation(self: *Controller) void {
        self.navigation.cancel();
    }

    pub fn finishLayout(self: *Controller, tree: *ui.Tree, now_ms: i64) void {
        if (self.layout.active(now_ms)) tree.* = self.layout.frame(tree, now_ms);
        self.layout.cancel();
    }
};

test "one controller decorates and reports every shared motion role" {
    const theme = @import("theme.zig").light;
    const id = interaction.Id.scoped(.brightness_meter, 0);
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.settings, 0), .bounds = .{ .x = 20, .y = 40, .width = 400, .height = 88 }, .label = "Brightness", .selected = true } });
    tree.add(.{ .meter = .{ .id = id, .bounds = .{ .x = 500, .y = 40, .width = 300, .height = 40 }, .value = 400, .track = theme.surface, .fill = theme.text, .thumb = theme.accent } });
    var controller = Controller{};
    controller.decorate(&tree, 0, false, id);
    tree.elements[1].meter.value = 800;
    controller.decorate(&tree, 10, false, id);
    try @import("std").testing.expect(controller.active(20));
}

test "routine destination cuts without retaining page navigation" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.settings, 0), .bounds = .{ .x = 20, .y = 40, .width = 400, .height = 88 }, .label = "Brightness", .selected = true } });
    var controller = Controller{};
    controller.navigation.running = true;
    controller.cutTo(&tree, 0, false, null);
    try @import("std").testing.expect(!controller.navigation.active(0));
    try @import("std").testing.expectEqual(interaction.Id.scoped(.settings, 0), tree.focusedId().?);
}
