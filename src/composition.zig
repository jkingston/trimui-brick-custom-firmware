// SPDX-License-Identifier: GPL-2.0-only
const ui = @import("ui_scene.zig");

pub const Selection = struct {
    element: ui.Element,
    bounds: ui.Rect,
};

pub const Plan = struct {
    base: ui.Tree,
    atlas: ui.Tree,
    selection: ?Selection,
};

pub fn split(tree: *const ui.Tree) Plan {
    return .{
        // The A133 mixer exposes a second ARGB UI plane, but physical device
        // observation found horizontal tearing while its crop moved between
        // selected rows. Keep the complete scene on the primary plane so every
        // navigation change is retired by one ordinary vblank page flip.
        .base = tree.*,
        .atlas = .{ .theme = tree.theme, .background = tree.background, .preserve_background = true },
        .selection = null,
    };
}

test "row navigation stays in the vblank-flipped primary scene" {
    const views = @import("ui.zig");
    const theme = @import("theme.zig").dark;
    var first = views.choice(theme, "Choice", &.{ "One", "Two", "Three" }, 0, null, "", "Back");
    var second = views.choice(theme, "Choice", &.{ "One", "Two", "Three" }, 1, null, "", "Back");
    const a = split(&first);
    const b = split(&second);
    try @import("std").testing.expect(!@import("std").meta.eql(@import("damage.zig").Scene.capture(&a.base), @import("damage.zig").Scene.capture(&b.base)));
    try @import("std").testing.expectEqualDeep(@import("damage.zig").Scene.capture(&a.atlas), @import("damage.zig").Scene.capture(&b.atlas));
    try @import("std").testing.expect(a.selection == null and b.selection == null);
}

test "base plus selected row reproduces the original scene" {
    const views = @import("ui.zig");
    const std = @import("std");
    const render = @import("render.zig");
    const theme = @import("theme.zig").light;
    var tree = views.choice(theme, "Choice", &.{ "One", "Two", "Three" }, 1, null, "", "Back");
    const plan = split(&tree);
    const expected = try std.testing.allocator.alloc(u32, render.width * render.height);
    defer std.testing.allocator.free(expected);
    const actual = try std.testing.allocator.alloc(u32, render.width * render.height);
    defer std.testing.allocator.free(actual);
    (render.Surface{ .pixels = expected }).render(&tree);
    const surface = render.Surface{ .pixels = actual };
    surface.render(&plan.base);
    try std.testing.expectEqualSlices(u32, expected, actual);
}

test "keyboard navigation remains a full primary scene and reproduces pixels" {
    const views = @import("ui.zig");
    const std = @import("std");
    const damage = @import("damage.zig");
    const render = @import("render.zig");
    const theme = @import("theme.zig").dark;
    var first = views.wifiPassword(theme, "Network", 0, "", false);
    var second = views.wifiPassword(theme, "Network", 17, "", false);
    const a = split(&first);
    const b = split(&second);
    try std.testing.expect(!std.meta.eql(damage.Scene.capture(&a.base), damage.Scene.capture(&b.base)));
    try std.testing.expectEqualDeep(damage.Scene.capture(&a.atlas), damage.Scene.capture(&b.atlas));
    try std.testing.expect(a.selection == null and b.selection == null);

    const expected = try std.testing.allocator.alloc(u32, render.width * render.height);
    defer std.testing.allocator.free(expected);
    const actual = try std.testing.allocator.alloc(u32, render.width * render.height);
    defer std.testing.allocator.free(actual);
    (render.Surface{ .pixels = expected }).render(&second);
    const surface = render.Surface{ .pixels = actual };
    surface.render(&b.base);
    try std.testing.expectEqualSlices(u32, expected, actual);
}
