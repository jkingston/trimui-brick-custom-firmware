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

/// A focus target for typography- and artwork-led surfaces. The screen owns
/// resting hierarchy; this component supplies identity, press feedback and
/// boundary response without adding a rail, underline or glow.
pub fn focusAnchor(result: *ui.Tree, scope: interaction.Id.Scope, index: usize, focused: bool, bounds: ui.Rect) void {
    const resolved = selection(scope, index, focused);
    result.add(.{ .focus_frame = .{
        .id = resolved.id,
        .state = resolved.state,
        .bounds = bounds,
        .presentation = .quiet,
    } });
}

/// Stable typography for sparse, editorial navigation. Focus may change
/// contrast and weight, but never text metrics: D-pad movement must not make
/// neighbouring labels snap, rewrap, or appear to breathe.
pub const EditorialScale = enum { control, compact, row, action };
pub const EditorialChoice = struct {
    label: []const u8,
    bounds: ui.Rect,
    focus_bounds: ui.Rect,
    scale: EditorialScale = .row,
    alignment: design.Alignment = .start,
};

pub fn editorialChoice(result: *ui.Tree, scope: interaction.Id.Scope, index: usize, focused: bool, spec: EditorialChoice) void {
    var text_font = switch (spec.scale) {
        .control => font.editorial_control,
        .compact => font.editorial_compact,
        .row => font.editorial_row,
        .action => font.editorial_action,
    };
    text_font.weight = if (focused) .semibold else .regular;
    text_font.alignment = spec.alignment;
    result.add(.{ .text = .{
        .bounds = spec.bounds,
        .value = spec.label,
        .color = if (focused) result.theme.text else result.theme.muted,
        .font = text_font,
    } });
    if (focused) focusAnchor(result, scope, index, true, spec.focus_bounds);
}

pub fn actionCard(result: *ui.Tree, scope: interaction.Id.Scope, index: usize, focused: bool, bounds: ui.Rect, eyebrow: []const u8, label: []const u8, detail: []const u8, emphasis: ui.CardEmphasis, label_lines: u8, detail_lines: u8) void {
    const resolved = selection(scope, index, focused);
    result.add(.{ .action_card = .{
        .id = resolved.id,
        .state = resolved.state,
        .bounds = bounds,
        .eyebrow = eyebrow,
        .label = label,
        .detail = detail,
        .emphasis = emphasis,
        .label_lines = label_lines,
        .detail_lines = detail_lines,
    } });
}

pub fn meter(result: *ui.Tree, id: interaction.Id, bounds: ui.Rect, value: u16) void {
    result.add(.{ .meter = .{ .id = id, .bounds = bounds, .value = @min(1000, value), .track = result.theme.surface, .fill = result.theme.text, .thumb = result.theme.accent } });
}

/// Discrete-value evidence for D-pad settings. The current stop is taller,
/// completed stops carry magnitude, and exact text remains optional context.
pub fn steppedMeter(result: *ui.Tree, id: interaction.Id, bounds: ui.Rect, value: u16, steps: u8) void {
    steppedMeterState(result, id, bounds, value, steps, true);
}

/// A stable value-stage slot may remain in the scene while another setting is
/// selected. The component, rather than its screen, owns the neutral styling.
pub fn steppedMeterState(result: *ui.Tree, id: interaction.Id, bounds: ui.Rect, value: u16, steps: u8, visible: bool) void {
    std.debug.assert(steps >= 2);
    result.add(.{ .meter = .{
        .id = id,
        .bounds = bounds,
        .value = if (visible) @min(1000, value) else 0,
        .visible = visible,
        .track = if (visible) result.theme.surface else result.theme.background,
        .fill = if (visible) result.theme.text else result.theme.background,
        .thumb = if (visible) result.theme.accent else result.theme.background,
        .presentation = .stepped,
        .steps = steps,
    } });
}

pub fn activity(result: *ui.Tree, bounds: ui.Rect, color: ui.Color) void {
    result.add(.{ .activity = .{ .bounds = bounds, .color = color } });
}

/// Compact battery evidence for a device row. The shape carries the glanceable
/// level; the percentage remains secondary for players who need precision.
pub fn batteryLevel(result: *ui.Tree, bounds: ui.Rect, percent: u8) void {
    var value: [5]u8 = undefined;
    const label = std.fmt.bufPrint(&value, "{d}%", .{percent}) catch return;
    var value_font = font.caption;
    value_font.size = 20;
    value_font.line_height = 28;
    value_font.alignment = .end;
    text(result, .{ .x = bounds.x, .y = bounds.y, .width = 50, .height = 28 }, label, result.theme.muted, value_font);
    result.add(.{ .battery = .{ .bounds = .{ .x = bounds.x + 62, .y = bounds.y + 2, .width = 52, .height = 24 }, .percent = percent } });
}

pub const NetworkStatus = enum { hidden, connected, attention };

pub const SystemStatus = struct {
    battery: ?u8 = null,
    network: NetworkStatus = .hidden,
};

/// The shell has a compact status cluster, not a persistent status bar. This
/// component owns its order and spacing so screens cannot accumulate arbitrary
/// chrome in the corner. Network bars communicate reachability, never RSSI.
pub fn systemStatus(result: *ui.Tree, status: SystemStatus) void {
    const right: u16 = design.geometry.width - design.spacing.margin;
    if (status.battery) |percent|
        result.add(.{ .battery = .{ .bounds = .{ .x = right - 60, .y = 40, .width = 60, .height = 28 }, .percent = percent } });
    if (status.network != .hidden)
        networkSignal(result, .{ .x = right -| @as(u16, if (status.battery == null) 28 else 104), .y = 43, .width = 25, .height = 22 }, status.network);
}

/// Constructed from scene primitives so software, GPU, screenshots, and damage
/// tracking share one icon without renderer-specific assets.
fn networkSignal(result: *ui.Tree, bounds: ui.Rect, status: NetworkStatus) void {
    const bar_width: u16 = 4;
    const gap: u16 = 3;
    for (0..4) |index| {
        const bar_height: u16 = 5 + @as(u16, @intCast(index)) * 4;
        result.add(.{ .bar = .{
            .bounds = .{
                .x = bounds.x + @as(u16, @intCast(index)) * (bar_width + gap),
                .y = bounds.y + bounds.height -| bar_height,
                .width = bar_width,
                .height = bar_height,
            },
            .color = if (status == .connected) result.theme.accent else result.theme.muted,
            .radius = 2,
        } });
    }
    if (status == .attention)
        result.add(.{ .bar = .{ .bounds = .{ .x = bounds.x + bounds.width - 5, .y = bounds.y, .width = 5, .height = 5 }, .color = result.theme.accent, .radius = 3 } });
}

/// Shared transient or terminal status surface. It occupies a stable status
/// band without becoming a floating toast: one hairline, one message, and one
/// semantic mark let the underlying screen remain the visual subject.
pub fn feedbackBanner(result: *ui.Tree, bounds: ui.Rect, feedback: Feedback) void {
    if (!feedback.visible()) return;
    const marker = switch (feedback.kind) {
        .failure => result.theme.danger,
        .warning => result.theme.muted,
        .progress, .success => result.theme.accent,
    };
    result.add(.{ .bar = .{ .bounds = .{ .x = bounds.x, .y = bounds.y, .width = bounds.width, .height = 1 }, .color = result.theme.border } });
    const status_width: u16 = 58;
    var message_font = font.caption;
    message_font.size = 24;
    message_font.line_height = 32;
    message_font.weight = .medium;
    message_font.ink_centered = true;
    text(result, .{ .x = bounds.x, .y = bounds.y + 12, .width = bounds.width - status_width, .height = message_font.line_height }, feedback.message, result.theme.text, message_font);
    const status = ui.Rect{ .x = bounds.x + bounds.width - status_width, .y = bounds.y + 12, .width = status_width, .height = 32 };
    if (feedback.kind == .progress) {
        activity(result, status, marker);
    } else {
        var status_font = font.control;
        status_font.alignment = .center;
        status_font.ink_centered = true;
        text(result, status, if (feedback.kind == .success) "✓" else "!", marker, status_font);
    }
}

pub const KeyboardInput = struct {
    selected: u8,
    uppercase: bool = false,
    symbols: bool = false,
};

pub fn keyboard(result: *ui.Tree, bounds: ui.Rect, value: KeyboardInput) void {
    result.add(.{ .keyboard = .{
        .id = interaction.Id.scoped(.keyboard_key, value.selected),
        .state = .focused,
        .bounds = bounds,
        .selected = value.selected,
        .uppercase = value.uppercase,
        .symbols = value.symbols,
    } });
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
        .horizontal => 56,
        else => 40,
    };
    const colour = result.theme.muted;
    switch (item.control) {
        .confirm, .back, .horizontal => {
            const symbol = switch (item.control) {
                .confirm => "A",
                .back => "B",
                // The bundled display face does not contain the Unicode
                // left-right arrow; ASCII chevrons remain crisp at device size.
                else => "<>",
            };
            if (item.control != .horizontal) {
                result.add(.{ .bar = .{ .bounds = .{ .x = x, .y = y + 1, .width = 38, .height = 38 }, .color = colour, .radius = 19 } });
                result.add(.{ .bar = .{ .bounds = .{ .x = x + 2, .y = y + 3, .width = 34, .height = 34 }, .color = result.background, .radius = 17 } });
            }
            var glyph_font = font.control;
            glyph_font.alignment = .center;
            result.add(.{ .text = .{ .bounds = .{ .x = x, .y = y, .width = size, .height = size }, .value = symbol, .color = colour, .font = glyph_font } });
        },
        .view, .filter => {
            for (0..2) |index| {
                const bounds = ui.Rect{ .x = x + @as(u16, @intCast(index)) * 36, .y = y + 14, .width = 28, .height = 12 };
                result.add(.{ .bar = .{ .bounds = bounds, .color = colour, .radius = 6 } });
                if (index != (if (item.control == .filter) @as(usize, 1) else 0)) result.add(.{ .bar = .{
                    .bounds = .{ .x = bounds.x + 2, .y = bounds.y + 2, .width = 24, .height = 8 },
                    .color = result.background,
                    .radius = 4,
                } });
            }
        },
        .menu => {
            result.add(.{ .bar = .{ .bounds = .{ .x = x + 2, .y = y + 6, .width = 58, .height = 28 }, .color = colour, .radius = 14 } });
            result.add(.{ .bar = .{ .bounds = .{ .x = x + 4, .y = y + 8, .width = 54, .height = 24 }, .color = result.background, .radius = 12 } });
            for (0..3) |index| result.add(.{ .bar = .{
                .bounds = .{ .x = x + 21 + @as(u16, @intCast(index)) * 9, .y = y + 18, .width = 4, .height = 4 },
                .color = colour,
                .radius = 2,
            } });
        },
    }
    text(result, .{ .x = x + size + geometry.hint_gap / 2, .y = y, .width = label_width, .height = 44 }, item.label, colour, font.control);
}

pub fn footer(result: *ui.Tree, items: []const Hint) void {
    if (items.len == 0) return;
    std.debug.assert(items.len <= 8);
    const bounds = ui.Rect{ .x = design.spacing.margin, .y = geometry.footer_y, .width = geometry.width - 2 * design.spacing.margin, .height = geometry.footer_height };

    const anchored_left = items[0].control == .back or items[0].control == .menu;
    const first_right: usize = if (anchored_left) 1 else 0;
    var label_widths: [8]u16 = @splat(0);
    var left_width: u16 = 0;
    if (anchored_left) {
        label_widths[0] = @min(desiredLabelWidth(items[0]), 240);
        left_width = hintWidth(items[0], label_widths[0]);
        hint(result, bounds.x, bounds.y, label_widths[0], items[0]);
    }

    const right_count = items.len - first_right;
    const group_gap: u16 = 28;
    const separation: u16 = if (anchored_left and right_count != 0) 48 else 0;
    const right_available = bounds.width -| left_width -| separation;
    var fixed_width: u16 = if (right_count > 1) @as(u16, @intCast(right_count - 1)) * group_gap else 0;
    var desired_total: u16 = 0;
    for (items[first_right..], first_right..) |item, item_index| {
        fixed_width +|= hintIconWidth(item) + geometry.hint_gap / 2;
        label_widths[item_index] = desiredLabelWidth(item);
        desired_total +|= label_widths[item_index];
    }
    const label_budget = right_available -| fixed_width;
    if (desired_total > label_budget and right_count != 0) {
        // Preserve the immediate/confirm action at the far right. Supporting
        // controls progressively become icon-only before groups can collide.
        const last = items.len - 1;
        label_widths[last] = @min(label_widths[last], label_budget);
        var remaining = label_budget - label_widths[last];
        var support_total: u16 = 0;
        for (first_right..last) |item_index| support_total +|= label_widths[item_index];
        for (first_right..last) |item_index| {
            const desired = label_widths[item_index];
            label_widths[item_index] = if (support_total == 0) 0 else @intCast(@as(u32, desired) * remaining / support_total);
            remaining -|= label_widths[item_index];
            support_total -|= desired;
        }
    }

    var cursor: u16 = bounds.x + bounds.width;
    var index = items.len;
    while (index > first_right) {
        index -= 1;
        const width = hintWidth(items[index], label_widths[index]);
        cursor -|= width;
        hint(result, cursor, bounds.y, label_widths[index], items[index]);
        if (index > first_right) cursor -|= 28;
    }
}

fn hintIconWidth(item: Hint) u16 {
    return switch (item.control) {
        .view, .filter, .menu => geometry.glyph_size,
        .horizontal => 56,
        else => 40,
    };
}

fn desiredLabelWidth(item: Hint) u16 {
    return @intCast(@min(@as(usize, 240), item.label.len * 22));
}

fn hintWidth(item: Hint, label_width: u16) u16 {
    return hintIconWidth(item) + geometry.hint_gap / 2 + label_width;
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
    for (tree.slice(), 0..) |element, index| {
        if (element != .text or std.mem.eql(u8, element.text.value, "A") or std.mem.eql(u8, element.text.value, "B")) continue;
        const label = element.text;
        for (tree.slice()[index + 1 ..]) |other| {
            if (other != .text or std.mem.eql(u8, other.text.value, "A") or std.mem.eql(u8, other.text.value, "B")) continue;
            const separate = @as(u32, label.bounds.x) + label.bounds.width <= other.text.bounds.x or
                @as(u32, other.text.bounds.x) + other.text.bounds.width <= label.bounds.x;
            try @import("std").testing.expect(separate);
        }
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

test "editorial focus preserves text geometry" {
    const theme = @import("theme.zig").dark;
    const spec = EditorialChoice{
        .label = "Library",
        .bounds = .{ .x = 48, .y = 120, .width = 400, .height = 68 },
        .focus_bounds = .{ .x = 48, .y = 120, .width = 440, .height = 72 },
        .scale = .row,
    };
    var idle = ui.Tree{ .theme = theme, .background = theme.background };
    editorialChoice(&idle, .library, 0, false, spec);
    var focused = ui.Tree{ .theme = theme, .background = theme.background };
    editorialChoice(&focused, .library, 0, true, spec);

    try std.testing.expectEqual(idle.elements[0].text.bounds, focused.elements[0].text.bounds);
    try std.testing.expectEqual(idle.elements[0].text.font.size, focused.elements[0].text.font.size);
    try std.testing.expectEqual(idle.elements[0].text.font.line_height, focused.elements[0].text.font.line_height);
    try std.testing.expectEqual(idle.elements[0].text.font.alignment, focused.elements[0].text.font.alignment);
    try std.testing.expectEqual(design.Weight.regular, idle.elements[0].text.font.weight);
    try std.testing.expectEqual(design.Weight.semibold, focused.elements[0].text.font.weight);
    try std.testing.expectEqual(interaction.Id.scoped(.library, 0), focused.focusedId().?);
}

test "action cards use the shared interaction contract" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    actionCard(&tree, .foyer, 1, true, .{ .x = 20, .y = 40, .width = 320, .height = 240 }, "Device", "Settings", "Display and audio", .secondary, 1, 1);
    try @import("std").testing.expectEqual(interaction.Id.scoped(.foyer, 1), tree.focusedId().?);
    try @import("std").testing.expect(tree.setInteraction(interaction.Id.scoped(.foyer, 1), .pressed));
    try @import("std").testing.expectEqual(interaction.State.pressed, tree.elements[0].action_card.state);
    try @import("std").testing.expectEqual(theme.selection_text, tree.elements[0].action_card.style.text);
}

test "keyboard owns the focused key identity and visible input mode" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    keyboard(&tree, .{ .x = 48, .y = 260, .width = 928, .height = 328 }, .{ .selected = 17, .uppercase = true, .symbols = true });
    try @import("std").testing.expectEqual(interaction.Id.scoped(.keyboard_key, 17), tree.focusedId().?);
    try @import("std").testing.expect(tree.elements[0].keyboard.uppercase);
    try @import("std").testing.expect(tree.elements[0].keyboard.symbols);
}

test "activity declaration is renderer-neutral" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    activity(&tree, .{ .x = 10, .y = 20, .width = 48, .height = 26 }, theme.accent);
    try @import("std").testing.expect(tree.hasActivity());
}

test "system status owns one compact top-right cluster" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    systemStatus(&tree, .{ .battery = 72, .network = .connected });
    try tree.validate();
    try @import("std").testing.expectEqual(@as(usize, 5), tree.len);
    try @import("std").testing.expectEqual(@as(u16, design.geometry.width - design.spacing.margin - 60), tree.elements[0].battery.bounds.x);
    for (tree.elements[1..5]) |element| {
        try @import("std").testing.expect(element == .bar);
        try @import("std").testing.expect(element.bar.bounds.x < tree.elements[0].battery.bounds.x);
    }
}

test "feedback status band uses a hairline and trailing semantic mark" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    feedbackBanner(&tree, .{ .x = 48, .y = 600, .width = 928, .height = 56 }, .{ .kind = .failure, .message = "Could not connect" });
    try @import("std").testing.expectEqual(@as(usize, 3), tree.len);
    try @import("std").testing.expectEqual(@as(u16, 928), tree.elements[0].bar.bounds.width);
    try @import("std").testing.expectEqual(@as(u16, 1), tree.elements[0].bar.bounds.height);
    try @import("std").testing.expectEqual("!", tree.elements[2].text.value);
    try @import("std").testing.expectEqual(theme.danger, tree.elements[2].text.color);
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
