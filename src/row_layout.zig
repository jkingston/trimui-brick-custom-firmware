// SPDX-License-Identifier: GPL-2.0-only
const ui = @import("ui_scene.zig");
const design = @import("design.zig");

pub fn overlay(row: ui.OverlayRow) [3]ui.Text {
    const padding = design.geometry.row_padding;
    var label_font = design.typeface.body;
    label_font.size = 38;
    label_font.line_height = 48;
    label_font.ink_centered = true;
    label_font.weight = if (row.selected) .medium else .regular;
    var detail_font = design.typeface.caption;
    detail_font.ink_centered = true;
    detail_font.size = 21;
    detail_font.line_height = 30;
    detail_font.alignment = .end;
    var value_font = detail_font;
    value_font.size = 26;
    value_font.line_height = 34;
    value_font.alignment = .end;
    const disclosure_width: u16 = if (row.disclosure) 38 else 0;
    const status_width = ui.stateAffordanceWidth(row.state);
    const has_metadata = row.detail.len != 0 or row.value.len != 0;
    const available = row.bounds.width - 2 * padding - status_width - disclosure_width;
    const minimum_label = @min(available, 240);
    const metadata_capacity = if (has_metadata) available -| minimum_label else 0;
    const column_gap: u16 = if (metadata_capacity >= 34) 16 else 0;
    const metadata_width = @min(@as(u16, 390), metadata_capacity -| 2 * column_gap);
    const detail_width: u16 = @intCast(@as(u32, metadata_width) * 175 / 390);
    const value_width = metadata_width - detail_width;
    const label_width = available -| detail_width -| value_width -| 2 * column_gap;
    const label_x = row.bounds.x + padding;
    const detail_x = label_x + label_width + column_gap;
    const value_x = detail_x + detail_width + column_gap;
    return .{
        .{ .bounds = .{ .x = label_x, .y = row.bounds.y + (row.bounds.height - label_font.line_height) / 2, .width = label_width, .height = label_font.line_height }, .value = row.label, .color = row.style.text, .font = label_font },
        .{ .bounds = .{ .x = detail_x, .y = row.bounds.y + (row.bounds.height - detail_font.line_height) / 2, .width = detail_width, .height = detail_font.line_height }, .value = row.detail, .color = row.style.detail, .font = detail_font },
        .{ .bounds = .{ .x = value_x, .y = row.bounds.y + (row.bounds.height - value_font.line_height) / 2, .width = value_width, .height = value_font.line_height }, .value = row.value, .color = row.style.text, .font = value_font },
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

test "metadata stays inline without moving the primary label" {
    const plain = ui.OverlayRow{ .bounds = .{ .x = 28, .y = 184, .width = 968, .height = 88 }, .label = "Auto-connect", .detail = "" };
    const supporting = ui.OverlayRow{ .bounds = plain.bounds, .label = "Private address", .detail = "Recommended", .value = "On" };
    const plain_parts = overlay(plain);
    const supporting_parts = overlay(supporting);
    try @import("std").testing.expectEqual(plain_parts[0].bounds.y, supporting_parts[0].bounds.y);
    try @import("std").testing.expectEqual(plain_parts[0].bounds.height, supporting_parts[0].bounds.height);
    try @import("std").testing.expect(@as(u32, supporting_parts[0].bounds.x) + supporting_parts[0].bounds.width <= supporting_parts[1].bounds.x);
    try @import("std").testing.expect(@as(u32, supporting_parts[1].bounds.x) + supporting_parts[1].bounds.width <= supporting_parts[2].bounds.x);
}

test "inline metadata yields to the label in a narrow row" {
    const row = ui.OverlayRow{ .bounds = .{ .x = 0, .y = 0, .width = 180, .height = 88 }, .label = "Network", .detail = "Connected", .value = "On", .disclosure = false };
    for (overlay(row)) |part|
        try @import("std").testing.expect(@as(u32, part.bounds.x) + part.bounds.width <= @as(u32, row.bounds.x) + row.bounds.width);
}
