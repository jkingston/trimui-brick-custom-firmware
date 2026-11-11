// SPDX-License-Identifier: GPL-2.0-only
const ui = @import("ui_scene.zig");

pub const columns = 10;
pub const count = 40;

pub fn keyBounds(bounds: ui.Rect, index: usize) ui.Rect {
    return (ui.Keyboard{ .bounds = bounds, .selected = @intCast(@min(index, count - 1)) }).keyBounds(index);
}
