// SPDX-License-Identifier: GPL-2.0-only
const ui = @import("ui_scene.zig");

pub const columns = 10;
pub const count = 40;

pub fn keyBounds(bounds: ui.Rect, index: usize) ui.Rect {
    const gap = 8;
    const width = (bounds.width - gap * (columns - 1)) / columns;
    const height = (bounds.height - gap * (count / columns - 1)) / (count / columns);
    return .{
        .x = bounds.x + @as(u16, @intCast(index % columns)) * (width + gap),
        .y = bounds.y + @as(u16, @intCast(index / columns)) * (height + gap),
        .width = width,
        .height = height,
    };
}
