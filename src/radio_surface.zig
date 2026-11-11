// SPDX-License-Identifier: GPL-2.0-only
//! Shared, honest initialization surface for device radios. It replaces a
//! fake selectable row with a page-scale state and keeps the next valid action
//! attached to the same stable focus identity.
const interaction = @import("interaction.zig");
const components = @import("ui_components.zig");
const scene = @import("ui_scene.zig");

pub const Spec = struct {
    title: []const u8,
    state: []const u8,
    subject: []const u8,
    detail: []const u8,
    scope: interaction.Id.Scope,
    progress: bool = false,
    back_label: []const u8 = "Settings",
    action_label: []const u8 = "",
};

pub fn status(theme: scene.Theme, spec: Spec) scene.Tree {
    var result = scene.Tree{ .theme = theme, .background = theme.background };
    components.header(&result, spec.title);
    components.text(&result, .{ .x = 664, .y = 48, .width = 312, .height = 34 }, spec.state, if (spec.progress) theme.accent else theme.muted, .{ .size = 20, .line_height = 28, .weight = .semibold, .alignment = .end });
    result.add(.{ .text_block = .{
        .bounds = .{ .x = 48, .y = 184, .width = 820, .height = 222 },
        .title = spec.subject,
        .detail = spec.detail,
        .color = theme.text,
        .detail_color = theme.muted,
        .title_font = .{ .size = 60, .line_height = 70, .weight = .semibold, .family = .display },
        .detail_font = .{ .size = 28, .line_height = 40 },
        .lines = 2,
        .detail_lines = 2,
        .gap = 22,
    } });
    if (spec.progress)
        components.activity(&result, .{ .x = 48, .y = 414, .width = 56, .height = 28 }, theme.accent);
    if (spec.action_label.len == 0) {
        components.footer(&result, &.{.{ .control = .back, .label = spec.back_label }});
    } else {
        components.editorialChoice(&result, spec.scope, 0, true, .{
            .label = spec.action_label,
            .bounds = .{ .x = 48, .y = 468, .width = 440, .height = 70 },
            .focus_bounds = .{ .x = 48, .y = 468, .width = 440, .height = 74 },
            .scale = .action,
        });
        components.footer(&result, &.{ .{ .control = .back, .label = spec.back_label }, .{ .control = .confirm, .label = spec.action_label } });
    }
    return result;
}

test "radio state keeps one stable focus target" {
    const std = @import("std");
    const theme = @import("theme.zig").dark;
    var tree = status(theme, .{ .title = "Wi-Fi", .state = "STARTING", .subject = "Join a network", .detail = "Wi-Fi is getting ready.", .scope = .wifi_list, .progress = true, .action_label = "Cancel" });
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
