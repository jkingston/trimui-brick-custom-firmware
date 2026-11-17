// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const interaction = @import("interaction.zig");
const motion = @import("motion.zig");
const ui = @import("ui_scene.zig");

const Item = struct { id: interaction.Id, bounds: ui.Rect };

/// Morphs stable interactive elements when a rebuilt viewport moves them.
/// Views remain declarative: logical identity is enough to keep shared rows
/// continuous and bring newly visible rows in from the same scroll direction.
pub const Controller = struct {
    from: ui.Tree = .{ .background = @import("theme.zig").light.background },
    progress: motion.Scalar = motion.Scalar.init(1000, .content),
    shift_x: i32 = 0,
    shift_y: i32 = 0,
    running: bool = false,

    pub fn begin(self: *Controller, from: *const ui.Tree, to: *const ui.Tree, now_ms: i64, reduced: bool) bool {
        self.running = false;
        var found = false;
        for (to.slice()) |element| {
            const destination = item(element) orelse continue;
            const source = find(from, destination.id) orelse continue;
            const dx = @as(i32, source.bounds.x) - destination.bounds.x;
            const dy = @as(i32, source.bounds.y) - destination.bounds.y;
            if (dx == 0 and dy == 0) continue;
            if (!found) {
                self.shift_x = dx;
                self.shift_y = dy;
                found = true;
            }
        }
        if (!found or reduced) return false;
        self.from = from.*;
        self.progress = motion.Scalar.init(0, .content);
        self.progress.retarget(1000, now_ms);
        self.running = true;
        return true;
    }

    pub fn cancel(self: *Controller) void {
        self.running = false;
    }

    pub fn active(self: *const Controller, now_ms: i64) bool {
        return self.running and self.progress.active(now_ms);
    }

    pub fn frame(self: *const Controller, destination: *const ui.Tree, now_ms: i64) ui.Tree {
        if (!self.running) return destination.*;
        const amount = std.math.clamp(self.progress.value(now_ms), 0, 1000);
        var result = destination.*;
        for (result.elements[0..result.len]) |*element| {
            const target = item(element.*) orelse continue;
            const start = if (find(&self.from, target.id)) |source|
                source.bounds
            else
                translated(target.bounds, self.shift_x, self.shift_y);
            setBounds(element, interpolate(start, target.bounds, amount));
        }
        return result;
    }
};

fn item(element: ui.Element) ?Item {
    return switch (element) {
        .focus_frame => |value| .{ .id = value.id, .bounds = value.bounds },
        .menu_row => |value| .{ .id = value.id, .bounds = value.bounds },
        .overlay_row => |value| .{ .id = value.id, .bounds = value.bounds },
        .artwork => |value| .{ .id = value.id, .bounds = value.bounds },
        else => null,
    };
}

fn find(tree: *const ui.Tree, id: interaction.Id) ?Item {
    if (id == .none) return null;
    for (tree.slice()) |element| {
        const candidate = item(element) orelse continue;
        if (candidate.id == id) return candidate;
    }
    return null;
}

fn setBounds(element: *ui.Element, bounds: ui.Rect) void {
    switch (element.*) {
        .focus_frame => |*value| value.bounds = bounds,
        .menu_row => |*value| value.bounds = bounds,
        .overlay_row => |*value| value.bounds = bounds,
        .artwork => |*value| value.bounds = bounds,
        else => {},
    }
}

fn translated(bounds: ui.Rect, dx: i32, dy: i32) ui.Rect {
    return .{
        .x = @intCast(std.math.clamp(@as(i32, bounds.x) + dx, 0, std.math.maxInt(u16))),
        .y = @intCast(std.math.clamp(@as(i32, bounds.y) + dy, 0, std.math.maxInt(u16))),
        .width = bounds.width,
        .height = bounds.height,
    };
}

fn interpolate(from: ui.Rect, to: ui.Rect, amount: i32) ui.Rect {
    return .{
        .x = lerp(from.x, to.x, amount),
        .y = lerp(from.y, to.y, amount),
        .width = lerp(from.width, to.width, amount),
        .height = lerp(from.height, to.height, amount),
    };
}

fn lerp(from: u16, to: u16, amount: i32) u16 {
    return @intCast(@as(i32, from) + @divTrunc((@as(i32, to) - from) * amount, 1000));
}

test "viewport rows retain visible geometry while the destination scrolls" {
    const theme = @import("theme.zig").light;
    var from = ui.Tree{ .theme = theme, .background = theme.background };
    from.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.test_scope, 0), .bounds = .{ .x = 20, .y = 100, .width = 200, .height = 80 }, .label = "Zero" } });
    from.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.test_scope, 1), .bounds = .{ .x = 20, .y = 200, .width = 200, .height = 80 }, .label = "One" } });
    var to = ui.Tree{ .theme = theme, .background = theme.background };
    to.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.test_scope, 1), .bounds = .{ .x = 20, .y = 100, .width = 200, .height = 80 }, .label = "One" } });
    to.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.test_scope, 2), .bounds = .{ .x = 20, .y = 200, .width = 200, .height = 80 }, .label = "Two" } });
    var controller = Controller{};
    try std.testing.expect(controller.begin(&from, &to, 0, false));
    const first = controller.frame(&to, 0);
    try std.testing.expectEqual(@as(u16, 200), first.elements[0].menu_row.bounds.y);
    try std.testing.expectEqual(@as(u16, 300), first.elements[1].menu_row.bounds.y);
    const settled = controller.frame(&to, 1000);
    try std.testing.expectEqual(@as(u16, 100), settled.elements[0].menu_row.bounds.y);
    try std.testing.expectEqual(@as(u16, 200), settled.elements[1].menu_row.bounds.y);
}

test "reduced motion keeps declarative destination geometry" {
    const theme = @import("theme.zig").light;
    var from = ui.Tree{ .theme = theme, .background = theme.background };
    from.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.test_scope, 0), .bounds = .{ .x = 0, .y = 100, .width = 100, .height = 80 }, .label = "One" } });
    var to = from;
    to.elements[0].menu_row.bounds.y = 200;
    var controller = Controller{};
    try std.testing.expect(!controller.begin(&from, &to, 0, true));
    try std.testing.expectEqual(@as(u16, 200), controller.frame(&to, 0).elements[0].menu_row.bounds.y);
}

test "rapid reversal starts at currently visible row geometry" {
    const theme = @import("theme.zig").light;
    var first = ui.Tree{ .theme = theme, .background = theme.background };
    first.add(.{ .menu_row = .{ .id = interaction.Id.scoped(.test_scope, 0), .bounds = .{ .x = 20, .y = 100, .width = 200, .height = 80 }, .label = "One" } });
    var second = first;
    second.elements[0].menu_row.bounds.y = 200;
    var controller = Controller{};
    try std.testing.expect(controller.begin(&first, &second, 0, false));
    const visible = controller.frame(&second, 50);
    try std.testing.expect(controller.begin(&visible, &first, 50, false));
    try std.testing.expectEqual(visible.elements[0].menu_row.bounds.y, controller.frame(&first, 50).elements[0].menu_row.bounds.y);
}
