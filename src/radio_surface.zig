// SPDX-License-Identifier: GPL-2.0-only
//! Shared, honest initialization surface for device radios. It replaces a
//! fake selectable row with a page-scale state and keeps the next valid action
//! attached to the same stable focus identity.
const interaction = @import("interaction.zig");
const components = @import("ui_components.zig");
const scene = @import("ui_scene.zig");

pub const Spec = struct {
    title: []const u8,
    subject: []const u8,
    detail: []const u8,
    scope: interaction.Id.Scope,
    progress: bool = false,
    back_label: []const u8 = "Settings",
    action_label: []const u8 = "",
};

pub fn status(theme: scene.Theme, spec: Spec) scene.Tree {
    var result = scene.Tree{ .theme = theme, .background = theme.background };
    components.text(&result, .{ .x = 48, .y = 42, .width = 640, .height = 42 }, spec.title, theme.muted, .{ .size = 23, .line_height = 32, .weight = .semibold });
    result.add(.{ .text_block = .{
        .bounds = .{ .x = 48, .y = 190, .width = 820, .height = 260 },
        .title = spec.subject,
        .detail = spec.detail,
        .color = theme.text,
        .detail_color = theme.muted,
        .title_font = .{ .size = 66, .line_height = 78, .weight = .semibold, .family = .display },
        .detail_font = .{ .size = 29, .line_height = 42 },
        .lines = 2,
        .detail_lines = 2,
        .gap = 24,
    } });
    components.focusAnchor(&result, spec.scope, 0, true, .{ .x = 32, .y = 170, .width = 856, .height = 300 });
    if (spec.progress)
        components.activity(&result, .{ .x = 48, .y = 482, .width = 48, .height = 28 }, theme.accent);
    if (spec.action_label.len == 0)
        components.footer(&result, &.{.{ .control = .back, .label = spec.back_label }})
    else
        components.footer(&result, &.{ .{ .control = .back, .label = spec.back_label }, .{ .control = .confirm, .label = spec.action_label } });
    return result;
}

test "radio state keeps one stable focus target" {
    const std = @import("std");
    const theme = @import("theme.zig").dark;
    var tree = status(theme, .{ .title = "Wi-Fi", .subject = "Turning Wi-Fi on", .detail = "This usually takes a moment.", .scope = .wifi_list, .progress = true, .action_label = "Cancel" });
    try tree.validate();
    try std.testing.expect(tree.focusedId() != null);
    var has_back = false;
    var has_action = false;
    for (tree.slice()) |element| if (element == .text) {
        has_back = has_back or std.mem.eql(u8, element.text.value, "Settings");
        has_action = has_action or std.mem.eql(u8, element.text.value, "Cancel");
    };
    try std.testing.expect(has_back);
    try std.testing.expect(has_action);
}
