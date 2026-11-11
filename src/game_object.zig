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
        // A loose front label is not a cover. Prefer complete editorial art,
        // then the authentic physical-media object that owns that label. This
        // keeps horizontal GBA labels and disc faces from floating in a large
        // portrait stage when an authored cartridge or disc is available.
        .cover => game.assets.cover orelse game.assets.card orelse game.assets.sprite orelse game.assets.preview,
        .cartridge, .spatial => game.assets.card orelse game.assets.sprite,
    };

    // A cover composition should remain immersive even before optional asset
    // matching completes. Bundled titles use authored art; unknown titles use
    // the deliberately neutral library cover rather than a placeholder panel.
    const authored_cover = sprite == null and (spec.presentation == .cover or spec.presentation == .spatial);
    if (authored_cover) {
        const bounds = safeBounds(spec.bounds);
        tree.add(.{ .cover = .{ .bounds = bounds, .kind = game.cover } });
        if (spec.dim != 0) tree.add(.{ .scrim = .{ .bounds = bounds, .color = tree.theme.background, .alpha = spec.dim } });
        if (spec.id != .none) tree.add(.{ .focus_frame = .{
            .id = spec.id,
            .state = if (spec.focused) .focused else .idle,
            .bounds = bounds,
            .presentation = .quiet,
        } });
        if (spec.active) activeMark(tree, bounds);
        return;
    }

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
    } });
    if (spec.active) activeMark(tree, safeBounds(spec.bounds));
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
    try std.testing.expectEqual(game.cover, tree.elements[0].cover.kind);
    try tree.validate();
}

test "cover presentation prefers complete media over a loose front label" {
    const label_pixels = [_]u32{0xff010203};
    const media_pixels = [_]u32{0xff040506};
    const texture = @import("asset_manifest.zig").Texture;
    var game = catalog.games[0];
    game.assets = .{
        .preview = texture{ .width = 1, .height = 1, .pixels = &label_pixels, .content_x = 0, .content_y = 0, .content_width = 1, .content_height = 1 },
        .sprite = texture{ .width = 1, .height = 1, .pixels = &media_pixels, .content_x = 0, .content_y = 0, .content_width = 1, .content_height = 1 },
    };
    const theme = @import("theme.zig").dark;
    var tree = scene.Tree{ .theme = theme, .background = theme.background };
    add(&tree, game, .{ .bounds = .{ .x = 48, .y = 120, .width = 320, .height = 360 } });
    try std.testing.expectEqual(@as(u32, 0xff040506), tree.elements[0].cartridge.sprite.?.pixels[0]);
}
