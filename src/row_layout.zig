// SPDX-License-Identifier: GPL-2.0-only
const ui = @import("ui_scene.zig");
const design = @import("design.zig");

pub fn overlay(row: ui.OverlayRow) [3]ui.Text {
    const padding = design.geometry.row_padding;
    var label_font = design.typeface.body;
    label_font.ink_centered = true;
    label_font.weight = if (row.selected) .medium else .regular;
    var detail_font = design.typeface.caption;
    detail_font.ink_centered = true;
    var value_font = detail_font;
    value_font.size = 34;
    value_font.line_height = 41;
    value_font.alignment = .end;
    const disclosure_width: u16 = if (row.disclosure) 38 else 0;
    const value_width: u16 = if (row.value.len != 0) 320 else 0;
    const tail: u16 = if (row.detail.len != 0) detail_font.line_height + 6 else 0;
    const label_y = row.bounds.y + (row.bounds.height -| (label_font.line_height + tail)) / 2;
    return .{
        .{ .bounds = .{ .x = row.bounds.x + padding, .y = label_y, .width = row.bounds.width - value_width - disclosure_width - 2 * padding, .height = label_font.line_height }, .value = row.label, .color = row.style.text, .font = label_font },
        .{ .bounds = .{ .x = row.bounds.x + padding, .y = label_y + label_font.line_height + 6, .width = row.bounds.width - disclosure_width - 2 * padding, .height = detail_font.line_height }, .value = row.detail, .color = row.style.detail, .font = detail_font },
        .{ .bounds = .{ .x = row.bounds.x + row.bounds.width - value_width - disclosure_width - padding, .y = row.bounds.y + (row.bounds.height - value_font.line_height) / 2, .width = value_width, .height = value_font.line_height }, .value = row.value, .color = row.style.text, .font = value_font },
    };
}

test "supporting row text and value stay within the row" {
    const row = ui.OverlayRow{
        .bounds = .{ .x = 28, .y = 184, .width = 968, .height = @import("ui_components.zig").supporting_row_height },
        .label = "A very long network name",
        .detail = "Connecting…",
        .value = "Strong · Secured",
        .selected = true,
        .disclosure = true,
    };
    for (overlay(row)) |part| {
        try @import("std").testing.expect(part.bounds.x >= row.bounds.x);
        try @import("std").testing.expect(@as(u32, part.bounds.x) + part.bounds.width <= @as(u32, row.bounds.x) + row.bounds.width);
        try @import("std").testing.expect(part.bounds.y >= row.bounds.y);
        try @import("std").testing.expect(@as(u32, part.bounds.y) + part.bounds.height <= @as(u32, row.bounds.y) + row.bounds.height);
    }
}
