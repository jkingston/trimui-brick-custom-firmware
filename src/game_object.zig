// SPDX-License-Identifier: GPL-2.0-only
//! The reusable visual identity of a game. Library density changes geometry,
//! never the object's state model or missing-art behavior.
const std = @import("std");
const catalog = @import("catalog.zig");
const design = @import("design.zig");
const interaction = @import("interaction.zig");
const scene = @import("ui_scene.zig");

pub const Spec = struct {
    bounds: scene.Rect,
    id: interaction.Id = .none,
    focused: bool = false,
    active: bool = false,
    dim: u8 = 0,
    tilt: i16 = 0,
    clip_left: u16 = 0,
};

pub fn add(tree: *scene.Tree, game: catalog.Game, spec: Spec) void {
    const bounds = safeBounds(spec.bounds);
    if (game.assets.cover) |texture| {
        tree.add(.{ .artwork = .{ .bounds = bounds, .texture = texture, .dim = spec.dim, .tilt = spec.tilt, .clip_left = spec.clip_left } });
    } else {
        // Missing art remains explicit. Demo cover recipes are never allowed to
        // masquerade as installed artwork in the product library.
        addText(tree, .{ .x = bounds.x + 20, .y = bounds.y + bounds.height / 3, .width = bounds.width -| 40, .height = bounds.height / 2 }, "No artwork", tree.theme.muted, .{ .size = 26, .line_height = 36, .weight = .medium, .alignment = .center });
    }
    if (spec.id != .none) tree.add(.{ .focus_frame = .{
        .id = spec.id,
        .state = if (spec.focused) .focused else .idle,
        .bounds = bounds,
        .presentation = .quiet,
    } });
    if (spec.active) activeMark(tree, bounds);
}

fn activeMark(tree: *scene.Tree, bounds: scene.Rect) void {
    addText(tree, .{ .x = bounds.x + 20, .y = bounds.y + bounds.height -| 48, .width = bounds.width -| 40, .height = 28 }, "PLAYING", tree.theme.accent, .{ .size = 18, .line_height = 26, .weight = .semibold });
}

fn safeBounds(bounds: scene.Rect) scene.Rect {
    return .{
        .x = bounds.x,
        .y = bounds.y,
        .width = @min(bounds.width, design.geometry.width -| bounds.x),
        .height = @min(bounds.height, design.geometry.height -| bounds.y),
    };
}

fn addText(tree: *scene.Tree, bounds: scene.Rect, value: []const u8, color: scene.Color, font: design.Font) void {
    tree.add(.{ .text = .{ .bounds = bounds, .value = value, .color = color, .font = font, .lines = 3 } });
}

test "missing artwork remains an authored focus object" {
    var game = catalog.games[0];
    game.assets = .{};
    const theme = @import("theme.zig").dark;
    var tree = scene.Tree{ .theme = theme, .background = theme.background };
    const id = interaction.Id.scoped(.library, 3);
    add(&tree, game, .{ .bounds = .{ .x = 48, .y = 120, .width = 320, .height = 360 }, .id = id, .focused = true });
    try std.testing.expectEqual(id, tree.focusedId().?);
    try std.testing.expectEqual(@as(usize, 2), tree.len);
    try std.testing.expectEqualStrings("No artwork", tree.elements[0].text.value);
    try tree.validate();
}

test "missing art identifies the game without invented imagery" {
    var game = catalog.games[0];
    game.cover = .library;
    game.assets = .{};
    const theme = @import("theme.zig").dark;
    var tree = scene.Tree{ .theme = theme, .background = theme.background };
    add(&tree, game, .{ .bounds = .{ .x = 48, .y = 120, .width = 320, .height = 360 } });
    try std.testing.expectEqualStrings("No artwork", tree.elements[0].text.value);
    try tree.validate();
}
