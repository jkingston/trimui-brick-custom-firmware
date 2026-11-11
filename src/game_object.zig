// SPDX-License-Identifier: GPL-2.0-only
//! The reusable visual identity of a game. Library density changes geometry,
//! never the object's state model or missing-art behavior.
const std = @import("std");
const catalog = @import("catalog.zig");
const design = @import("design.zig");
const interaction = @import("interaction.zig");
const scene = @import("ui_scene.zig");

pub const Presentation = enum { cover, cartridge, spatial };

pub const Spec = struct {
    bounds: scene.Rect,
    presentation: Presentation = .cover,
    id: interaction.Id = .none,
    focused: bool = false,
    active: bool = false,
    dim: u8 = 0,
    tilt: i16 = 0,
    clip_left: u16 = 0,
};

pub fn add(tree: *scene.Tree, game: catalog.Game, spec: Spec) void {
    const sprite = switch (spec.presentation) {
        .cover => game.assets.cover,
        .cartridge, .spatial => game.assets.card orelse game.assets.sprite,
    };
    if (sprite == null and game.assets.preview == null)
        return authoredIdentity(tree, game, spec);

    tree.add(.{ .cartridge = .{
        .id = spec.id,
        .state = if (spec.focused) .focused else .idle,
        .bounds = spec.bounds,
        .platform = game.platform_id,
        .texture = game.assets.preview,
        .sprite = sprite,
        .selected = spec.focused,
        .dim = spec.dim,
        .tilt = spec.tilt,
        .clip_left = spec.clip_left,
        .plain_fallback = spec.presentation == .cover,
    } });
    if (spec.active) activeMark(tree, safeBounds(spec.bounds));
}

fn authoredIdentity(tree: *scene.Tree, game: catalog.Game, spec: Spec) void {
    if (spec.bounds.x >= design.geometry.width or spec.bounds.y >= design.geometry.height) return;
    const bounds = safeBounds(spec.bounds);
    if (spec.presentation != .spatial)
        tree.add(.{ .bar = .{ .bounds = bounds, .color = tree.theme.surface, .radius = design.geometry.radius } });
    addText(tree, .{ .x = bounds.x + 20, .y = bounds.y + 20, .width = bounds.width -| 40, .height = 36 }, game.system, if (spec.focused or spec.active) tree.theme.accent else tree.theme.muted, .{ .size = 20, .line_height = 28, .weight = .semibold, .alignment = if (spec.presentation == .spatial) .center else .start });
    addText(tree, .{ .x = bounds.x + 20, .y = bounds.y + @min(@as(u16, 82), bounds.height / 3), .width = bounds.width -| 40, .height = bounds.height -| 112 }, game.title, tree.theme.text, .{
        .size = if (spec.focused) 48 else 30,
        .line_height = if (spec.focused) 58 else 38,
        .weight = if (spec.focused) .semibold else .medium,
        .family = .display,
        .alignment = if (spec.presentation == .spatial) .center else .start,
    });
    if (spec.active) activeMark(tree, bounds);
    if (spec.id != .none) tree.add(.{ .focus_frame = .{
        .id = spec.id,
        .state = if (spec.focused) .focused else .idle,
        .bounds = bounds,
        .presentation = .quiet,
    } });
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
    try std.testing.expect(tree.len >= 4);
    try tree.validate();
}
