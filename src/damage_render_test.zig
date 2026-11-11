// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const damage = @import("damage.zig");
const render = @import("render.zig");
const settings = @import("settings.zig");
const theme = @import("theme.zig");
const ui = @import("ui.zig");
const wifi = @import("wifi.zig");

const Harness = struct {
    pages: [2][]u32,
    expected: []u32,
    scenes: [2]damage.Scene,
    last_damage: damage.RectSet = .{},
    draw_page: usize = 1,

    fn init(pages: [2][]u32, expected: []u32, initial: *const ui.Tree) !Harness {
        for (pages) |pixels| (render.Surface{ .pixels = pixels }).render(initial);
        return .{
            .pages = pages,
            .expected = expected,
            .scenes = @splat(damage.Scene.capture(initial)),
        };
    }

    fn show(self: *Harness, tree: *const ui.Tree) !void {
        const next_scene = damage.Scene.captureAfter(tree, &self.scenes[self.draw_page]);
        const pending = damage.Scene.changes(&self.scenes[self.draw_page], &next_scene);
        self.last_damage = pending;
        (render.Surface{ .pixels = self.pages[self.draw_page] }).renderDamage(tree, &pending);
        (render.Surface{ .pixels = self.expected }).render(tree);
        try std.testing.expectEqualSlices(u32, self.expected, self.pages[self.draw_page]);
        self.scenes[self.draw_page] = next_scene;
        self.draw_page = (self.draw_page + 1) % self.pages.len;
    }
};

test "buffer-age damage rendering is pixel-identical across navigation" {
    const pixel_count = render.width * render.height;
    const storage = try std.testing.allocator.alloc(u32, pixel_count * 4);
    defer std.testing.allocator.free(storage);
    const pages = [_][]u32{
        storage[0 * pixel_count .. 1 * pixel_count],
        storage[1 * pixel_count .. 2 * pixel_count],
        storage[2 * pixel_count .. 3 * pixel_count],
    };
    const expected = storage[3 * pixel_count .. 4 * pixel_count];
    const values = settings.Values{};
    const tree = ui.settings(0, values, "Off", "Off");
    for (pages[0..2]) |pixels| (render.Surface{ .pixels = pixels }).render(&tree);
    var scene = damage.Scene.capture(&tree);
    var tracker = try damage.PageTracker.init(2);
    var draw_page: usize = 1;
    const selections = [_]usize{ 1, 2, 3, 4, 5, 6, 5, 3, 0, 2, 2, 6 };
    for (selections) |selected| {
        var next = ui.settings(selected, values, "Off", "Off");
        const next_scene = damage.Scene.capture(&next);
        const changed = damage.Scene.changes(&scene, &next_scene);
        tracker.invalidate(&changed);
        const pending = tracker.take(draw_page);
        (render.Surface{ .pixels = pages[draw_page] }).renderDamage(&next, &pending);
        (render.Surface{ .pixels = expected }).render(&next);
        try std.testing.expectEqualSlices(u32, expected, pages[draw_page]);
        scene = next_scene;
        draw_page = (draw_page + 1) % 2;
    }
}

test "buffer-age damage rendering is pixel-identical across dissimilar screens" {
    const pixel_count = render.width * render.height;
    const storage = try std.testing.allocator.alloc(u32, pixel_count * 3);
    defer std.testing.allocator.free(storage);
    const pages = [2][]u32{
        storage[0 * pixel_count .. 1 * pixel_count],
        storage[1 * pixel_count .. 2 * pixel_count],
    };
    const expected = storage[2 * pixel_count .. 3 * pixel_count];

    var first = ui.foyer(theme.light, 0);
    var harness = try Harness.init(pages, expected, &first);

    var next = ui.foyer(theme.light, 1);
    try harness.show(&next);
    next = ui.overlayPause(theme.light, "A long game title", 0, 0, "Balanced", "");
    try harness.show(&next);
    next = ui.overlayPause(theme.light, "A long game title", 4, 2, "Performance", "Saved");
    try harness.show(&next);
    next = ui.wifiPassword(theme.light, "Test network", .{ .selected = 0 }, "hunter2", false);
    try harness.show(&next);
    next = ui.wifiPassword(theme.light, "Test network", .{ .selected = 31 }, "hunter2", true);
    try harness.show(&next);
    next = ui.confirmation(theme.light, "Remove game?", "Example", "This cannot be undone.", "Remove", 0);
    try harness.show(&next);
    next = ui.confirmation(theme.light, "Remove game?", "Example", "This cannot be undone.", "Remove", 1);
    try harness.show(&next);
    next = ui.languageProof(theme.dark);
    try harness.show(&next);
    next = ui.settings(0, .{}, "Connected", "Off");
    try harness.show(&next);
}

test "returning to retained buffer contents requires no repaint" {
    const count = render.width * render.height;
    const pixels = try std.testing.allocator.alloc(u32, count * 3);
    defer std.testing.allocator.free(pixels);
    var first = ui.settings(0, .{}, "On", "Off");
    var second = ui.settings(1, .{}, "On", "Off");
    var harness = try Harness.init(.{ pixels[0..count], pixels[count .. count * 2] }, pixels[count * 2 ..], &first);
    try harness.show(&second);
    try std.testing.expect(harness.last_damage.slice().len != 0);
    for (0..8) |_| {
        try harness.show(&first);
        try std.testing.expectEqual(@as(usize, 0), harness.last_damage.slice().len);
        try harness.show(&second);
        try std.testing.expectEqual(@as(usize, 0), harness.last_damage.slice().len);
    }
}

test "Wi-Fi entry, status updates and return preserve both framebuffer pages" {
    const count = render.width * render.height;
    const pixels = try std.testing.allocator.alloc(u32, count * 3);
    defer std.testing.allocator.free(pixels);
    var tree = ui.settings(0, .{}, "Unavailable", "Off");
    var harness = try Harness.init(.{ pixels[0..count], pixels[count .. count * 2] }, pixels[count * 2 ..], &tree);
    var state = wifi.Model{};
    for (0..3) |_| {
        for ([_]wifi.RadioState{ .unavailable, .off, .starting, .ready, .failed }) |radio| {
            state.snapshot.radio = radio;
            tree = ui.wifiPicker(theme.light, &state);
            try harness.show(&tree);
        }
        state.snapshot.radio = .ready;
        state.snapshot.network_count = 8;
        for (state.snapshot.networks[0..8], 0..) |*network, i| {
            try network.name.set(if (i % 2 == 0) "Test network" else "A longer network name");
            network.security = .wpa2_personal;
            network.signal = .strong;
        }
        for (0..9) |selected| {
            state.selected = selected;
            tree = ui.wifiPicker(theme.light, &state);
            try harness.show(&tree);
        }
        state.snapshot.network_count = 0;
        state.selected = 0;
        tree = ui.settings(0, .{}, "On", "Off");
        try harness.show(&tree);
    }
}

test "partial invalidation clears complete overlapping alpha elements" {
    const count = render.width * render.height;
    const pixels = try std.testing.allocator.alloc(u32, count * 3);
    defer std.testing.allocator.free(pixels);
    var tree = ui.Tree{ .theme = theme.light, .background = theme.light.background };
    tree.add(.{ .bar = .{ .bounds = .{ .x = 10, .y = 10, .width = 30, .height = 30 }, .color = theme.light.text, .radius = 0 } });
    tree.add(.{ .scrim = .{ .bounds = .{ .x = 30, .y = 20, .width = 50, .height = 50 }, .color = theme.light.text, .alpha = 127 } });
    var harness = try Harness.init(.{ pixels[0..count], pixels[count .. count * 2] }, pixels[count * 2 ..], &tree);
    for (0..8) |i| {
        tree.elements[0].bar.color = if (i % 2 == 0) theme.light.background else theme.light.text;
        try harness.show(&tree);
    }
}

test "clipped artwork invalidates pixels left of its layout bounds" {
    const count = render.width * render.height;
    const pixels = try std.testing.allocator.alloc(u32, count * 3);
    defer std.testing.allocator.free(pixels);
    const artwork = [_]u32{ 0xffa03010, 0x80206040, 0, 0xff105090 };
    var tree = ui.Tree{ .theme = theme.light, .background = theme.light.background };
    tree.add(.{ .cartridge = .{
        .bounds = .{ .x = 40, .y = 20, .width = 60, .height = 60 },
        .platform = "gba",
        .texture = null,
        .sprite = .{ .width = 2, .height = 2, .content_x = 0, .content_y = 0, .content_width = 2, .content_height = 2, .pixels = &artwork },
    } });
    var harness = try Harness.init(.{ pixels[0..count], pixels[count .. count * 2] }, pixels[count * 2 ..], &tree);
    for ([_]u16{ 17, 17, 0, 50, 50, 0 }) |clip| {
        tree.elements[0].cartridge.clip_left = clip;
        try harness.show(&tree);
    }
}

test "row background batching preserves overlapping compositing order" {
    const count = render.width * render.height;
    const pixels = try std.testing.allocator.alloc(u32, count * 3);
    defer std.testing.allocator.free(pixels);
    var tree = ui.settings(0, .{}, "On", "Off");
    tree.add(.{ .scrim = .{ .bounds = .{ .x = 100, .y = 170, .width = 200, .height = 170 }, .color = theme.light.danger, .alpha = 127 } });
    var harness = try Harness.init(.{ pixels[0..count], pixels[count .. count * 2] }, pixels[count * 2 ..], &tree);
    for (0..6) |i| {
        tree.elements[tree.len - 1].scrim.alpha = @intCast(30 + 30 * i);
        try harness.show(&tree);
    }
}

test "row content changes repaint only ink while preserving overlapping alpha" {
    const count = render.width * render.height;
    const pixels = try std.testing.allocator.alloc(u32, count * 3);
    defer std.testing.allocator.free(pixels);
    var tree = ui.Tree{ .theme = theme.light, .background = theme.light.background };
    tree.add(.{ .overlay_row = .{ .bounds = .{ .x = 28, .y = 138, .width = 968, .height = 108 }, .label = "Initial label", .detail = "", .value = "Off", .selected = false } });
    tree.add(.{ .scrim = .{ .bounds = .{ .x = 100, .y = 170, .width = 800, .height = 30 }, .color = theme.light.danger, .alpha = 127 } });
    var harness = try Harness.init(.{ pixels[0..count], pixels[count .. count * 2] }, pixels[count * 2 ..], &tree);
    const labels = [_][]const u8{ "Short", "A much longer label with descenders gyp", "", "日本語", "العربية", "Again" };
    for (labels, 0..) |label, i| {
        tree.elements[0].overlay_row.label = label;
        tree.elements[0].overlay_row.value = if (i % 2 == 0) "On" else "";
        tree.elements[0].overlay_row.detail = if (i % 3 == 0) "Detail with descenders" else "";
        try harness.show(&tree);
        var area: usize = 0;
        for (harness.last_damage.slice()) |rect| area += @as(usize, rect.width) * rect.height;
        try std.testing.expect(area < 968 * 108);
    }
}

test "clipped repaint preserves pixels outside requested damage" {
    const count = render.width * render.height;
    const pixels = try std.testing.allocator.alloc(u32, count * 2);
    defer std.testing.allocator.free(pixels);
    const actual = pixels[0..count];
    const expected = pixels[count..];
    @memset(actual, 0xdeadbeef);
    var tree = ui.settings(0, .{}, "On", "Off");
    tree.add(.{ .scrim = .{ .bounds = .{ .x = 100, .y = 100, .width = 100, .height = 100 }, .color = theme.light.text, .alpha = 127 } });
    var dirty = damage.RectSet{};
    dirty.add(.{ .x = 105, .y = 140, .width = 30, .height = 36 });
    dirty.add(.{ .x = 151, .y = 155, .width = 21, .height = 29 });
    (render.Surface{ .pixels = actual }).renderDamage(&tree, &dirty);
    (render.Surface{ .pixels = expected }).render(&tree);
    for (actual, expected, 0..) |a, b, i| try std.testing.expectEqual(if (damage.containsPixel(dirty.slice(), i % render.width, i / render.width)) b else @as(u32, 0xdeadbeef), a);
}

test "keyboard navigation damages two keys and redraws changed character sets" {
    const count = render.width * render.height;
    const pixels = try std.testing.allocator.alloc(u32, count * 3);
    defer std.testing.allocator.free(pixels);
    var tree = ui.wifiPassword(theme.light, "Example", .{ .selected = 0 }, "", false);
    var harness = try Harness.init(.{ pixels[0..count], pixels[count .. count * 2] }, pixels[count * 2 ..], &tree);
    for (0..40) |index| {
        tree = ui.wifiPassword(theme.light, "Example", .{ .selected = @intCast(index) }, "", false);
        try harness.show(&tree);
        var area: usize = 0;
        for (harness.last_damage.slice()) |rect| if (damage.intersection(rect, .{ .x = 48, .y = 260, .width = 928, .height = 328 })) |part| {
            area += @as(usize, part.width) * part.height;
        };
        try std.testing.expect(area < 20000);
    }
    for (0..8) |step| {
        tree = ui.wifiPassword(theme.light, "Example", .{ .selected = 17 }, "", false);
        for (tree.elements[0..tree.len]) |*element| if (element.* == .keyboard) {
            element.keyboard.focus_offset_x = @intCast(step * 8);
            element.keyboard.state = if (step % 2 == 0) .focused else .pressed;
        };
        try harness.show(&tree);
        var area: usize = 0;
        for (harness.last_damage.slice()) |rect| if (damage.intersection(rect, .{ .x = 48, .y = 260, .width = 928, .height = 328 })) |part| {
            area += @as(usize, part.width) * part.height;
        };
        try std.testing.expect(area < 20000);
    }
    for (0..8) |index| {
        tree = ui.wifiPassword(theme.light, "Example", .{ .selected = @intCast(index) }, "", index % 3 == 0);
        for (tree.elements[0..tree.len]) |*element| if (element.* == .keyboard) {
            element.keyboard.symbols = index % 3 == 1;
        };
        try harness.show(&tree);
    }
}
