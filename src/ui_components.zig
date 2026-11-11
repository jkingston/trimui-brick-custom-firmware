// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const design = @import("design.zig");
const font = design.typeface;
const geometry = design.geometry;
const input = @import("input.zig");
const interaction = @import("interaction.zig");
const ui = @import("ui_scene.zig");

pub const Hint = struct { control: input.HintControl, label: []const u8 };

pub const FeedbackKind = enum { progress, success, warning, failure };
pub const Feedback = struct {
    kind: FeedbackKind = .progress,
    message: []const u8 = "",

    pub fn visible(self: Feedback) bool {
        return self.message.len != 0;
    }

    pub fn eql(self: Feedback, other: Feedback) bool {
        return self.kind == other.kind and std.mem.eql(u8, self.message, other.message);
    }
};

pub const FeedbackPhase = enum { hidden, visible };
pub const FeedbackLifecycle = struct {
    feedback: Feedback = .{},
    phase: FeedbackPhase = .hidden,
    deadline_ms: ?i64 = null,
    dwell_ms: i64 = 1800,

    pub fn show(self: *FeedbackLifecycle, value: Feedback, now_ms: i64) void {
        self.feedback = value;
        self.phase = if (value.visible()) .visible else .hidden;
        self.deadline_ms = if (value.visible() and value.kind != .progress) now_ms + self.dwell_ms else null;
    }

    pub fn dismiss(self: *FeedbackLifecycle, now_ms: i64) void {
        if (self.phase == .hidden) return;
        self.deadline_ms = now_ms;
    }

    pub fn tick(self: *FeedbackLifecycle, now_ms: i64) bool {
        if (self.deadline_ms == null or now_ms < self.deadline_ms.?) return false;
        self.phase = .hidden;
        self.feedback = .{};
        self.deadline_ms = null;
        return true;
    }

    pub fn timeout(self: FeedbackLifecycle, now_ms: i64) i32 {
        const due = self.deadline_ms orelse return -1;
        return @intCast(@max(@as(i64, 0), @min(due - now_ms, @as(i64, @import("std").math.maxInt(i32)))));
    }
};

/// Shared declaration for selectable rows. Screen code supplies content and
/// geometry; this component supplies stable identity and interaction state.
pub const Selectable = struct {
    id: interaction.Id,
    bounds: ui.Rect,
    label: []const u8,
    detail: []const u8 = "",
    value: []const u8 = "",
    state: interaction.State = .idle,
    disclosure: bool = true,
    label_font: design.Font = font.body,
    lines: u8 = 1,

    pub fn menu(self: Selectable, result: *ui.Tree) void {
        result.add(.{ .menu_row = .{
            .id = self.id,
            .state = self.state,
            .bounds = self.bounds,
            .label = self.label,
            .detail = self.detail,
            .disclosure = self.disclosure,
            .label_font = self.label_font,
            .lines = self.lines,
        } });
    }

    pub fn overlay(self: Selectable, result: *ui.Tree) void {
        result.add(.{ .overlay_row = .{
            .id = self.id,
            .state = self.state,
            .bounds = self.bounds,
            .label = self.label,
            .detail = self.detail,
            .value = self.value,
            .disclosure = self.disclosure,
        } });
    }

    pub fn frame(self: Selectable, result: *ui.Tree) void {
        result.add(.{ .focus_frame = .{
            .id = self.id,
            .state = self.state,
            .bounds = self.bounds,
        } });
    }
};

pub fn selection(scope: interaction.Id.Scope, index: usize, focused: bool) struct { id: interaction.Id, state: interaction.State } {
    return .{ .id = interaction.Id.scoped(scope, index), .state = if (focused) .focused else .idle };
}

pub fn selectable(scope: interaction.Id.Scope, index: usize, focused: bool, bounds: ui.Rect, label: []const u8) Selectable {
    const resolved = selection(scope, index, focused);
    return .{ .id = resolved.id, .state = resolved.state, .bounds = bounds, .label = label };
}

pub const single_row_height: u16 = 88;
pub const supporting_row_height: u16 = 108;

pub fn continuation(result: *ui.Tree, top: u16, bottom: u16, has_before: bool, has_after: bool) void {
    var indicator_font = font.caption;
    indicator_font.alignment = .center;
    indicator_font.size = 24;
    indicator_font.line_height = 30;
    text(result, .{ .x = 956, .y = top, .width = 40, .height = 34 }, if (has_before) "↑" else "", result.theme.muted, indicator_font);
    text(result, .{ .x = 956, .y = bottom -| 34, .width = 40, .height = 34 }, if (has_after) "↓" else "", result.theme.muted, indicator_font);
}

pub fn text(result: *ui.Tree, bounds: ui.Rect, value: []const u8, color: ui.Color, text_font: design.Font) void {
    result.add(.{ .text = .{ .bounds = bounds, .value = value, .color = color, .font = text_font } });
}

pub fn header(result: *ui.Tree, title: []const u8) void {
    text(result, .{ .x = design.spacing.margin, .y = geometry.header_y, .width = 800, .height = 58 }, title, result.theme.text, font.title);
}

pub fn hint(result: *ui.Tree, x: u16, y: u16, label_width: u16, item: Hint) void {
    const size: u16 = switch (item.control) {
        .view, .filter, .menu => geometry.glyph_size,
        else => 40,
    };
    const colour = result.theme.muted;
    switch (item.control) {
        .confirm, .back, .horizontal => {
            const symbol = switch (item.control) {
                .confirm => "A",
                .back => "B",
                else => "↔",
            };
            if (item.control != .horizontal) {
                result.add(.{ .bar = .{ .bounds = .{ .x = x, .y = y + 1, .width = 38, .height = 38 }, .color = colour, .radius = 19 } });
                result.add(.{ .bar = .{ .bounds = .{ .x = x + 2, .y = y + 3, .width = 34, .height = 34 }, .color = result.background, .radius = 17 } });
            }
            var glyph_font = font.control;
            glyph_font.alignment = .center;
            result.add(.{ .text = .{ .bounds = .{ .x = x, .y = y, .width = size, .height = size }, .value = symbol, .color = colour, .font = glyph_font } });
        },
        .view, .filter, .menu => {
            const upper = item.control != .menu;
            const count: u16 = if (upper) 2 else 3;
            const key_width: u16 = if (upper) 28 else 18;
            const key_height: u16 = if (upper) 12 else 18;
            const gap: u16 = if (upper) 8 else 5;
            for (0..count) |index| {
                const bounds = ui.Rect{ .x = x + @as(u16, @intCast(index)) * (key_width + gap), .y = y + (40 - key_height) / 2, .width = key_width, .height = key_height };
                result.add(.{ .bar = .{ .bounds = bounds, .color = colour, .radius = key_height / 2 } });
                if (index != (if (item.control == .filter) @as(usize, 1) else 0)) result.add(.{ .bar = .{
                    .bounds = .{ .x = bounds.x + 2, .y = bounds.y + 2, .width = key_width - 4, .height = key_height - 4 },
                    .color = result.background,
                    .radius = key_height / 2 - 2,
                } });
            }
        },
    }
    text(result, .{ .x = x + size + geometry.hint_gap / 2, .y = y, .width = label_width, .height = 44 }, item.label, colour, font.control);
}

pub fn footer(result: *ui.Tree, items: []const Hint) void {
    if (items.len == 0) return;
    const bounds = ui.Rect{ .x = design.spacing.margin, .y = geometry.footer_y, .width = geometry.width - 2 * design.spacing.margin, .height = 44 };
    const slot_width = bounds.width / @as(u16, @intCast(items.len));
    for (items, 0..) |item, index| {
        const icon: u16 = switch (item.control) {
            .view, .filter, .menu => geometry.glyph_size,
            else => 40,
        };
        const x = bounds.x + @as(u16, @intCast(index)) * slot_width;
        hint(result, x, bounds.y, slot_width -| icon -| 8, item);
    }
}

test "footer controls stay within the screen" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    footer(&tree, &.{ .{ .control = .back, .label = "Back" }, .{ .control = .confirm, .label = "Select" } });
    for (tree.slice()) |element| {
        const bounds = switch (element) {
            inline else => |value| value.bounds,
        };
        try @import("std").testing.expect(@as(u32, bounds.x) + bounds.width <= geometry.width);
    }
}

test "four long footer controls use bounded non-overlapping slots" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    footer(&tree, &.{
        .{ .control = .back, .label = "Return to settings" },
        .{ .control = .filter, .label = "Choose system" },
        .{ .control = .view, .label = "Change view" },
        .{ .control = .confirm, .label = "Select item" },
    });
    for (tree.slice()) |element| {
        const bounds = switch (element) {
            inline else => |value| value.bounds,
        };
        try @import("std").testing.expect(@as(u32, bounds.x) + bounds.width <= geometry.width);
    }
}

test "standard supporting rows fit both text lines" {
    const required = font.body.line_height + 6 + font.caption.line_height;
    try @import("std").testing.expect(supporting_row_height >= required);
    try @import("std").testing.expect(single_row_height >= font.body.line_height);
}

test "selectable owns identity and interaction state" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    const selected = selection(.test_scope, 3, true);
    (Selectable{ .id = selected.id, .state = selected.state, .bounds = .{ .x = 0, .y = 0, .width = 100, .height = 88 }, .label = "Play" }).menu(&tree);
    try @import("std").testing.expectEqual(selected.id, tree.focusedId().?);
}

test "selectable frames share row identity and state" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    selectable(.library, 2, true, .{ .x = 20, .y = 40, .width = 100, .height = 80 }, "").frame(&tree);
    try @import("std").testing.expectEqual(interaction.Id.scoped(.library, 2), tree.focusedId().?);
}

test "feedback lifecycle does not leave completion notices indefinitely" {
    var notice = FeedbackLifecycle{};
    notice.show(.{ .kind = .success, .message = "Saved" }, 0);
    try @import("std").testing.expectEqual(FeedbackPhase.visible, notice.phase);
    try @import("std").testing.expectEqual(@as(i32, 1800), notice.timeout(0));
    _ = notice.tick(notice.dwell_ms);
    try @import("std").testing.expectEqual(FeedbackPhase.hidden, notice.phase);
    try @import("std").testing.expectEqual(@as(i32, -1), notice.timeout(5000));
}
