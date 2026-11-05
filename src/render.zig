// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const ui = @import("ui.zig");
const text_pango = @import("text_pango.zig");

pub const width = 1024;
pub const height = 768;

pub const Surface = struct {
    pixels: []u32,

    pub fn render(self: Surface, tree: *const ui.Tree) void {
        if (!tree.preserve_background) @memset(self.pixels, pack(tree.background));
        for (tree.slice()) |element| switch (element) {
            .bar => |bar| self.fill(bar.bounds, bar.color),
            .scrim => |scrim| self.fillAlpha(scrim.bounds, scrim.color, scrim.alpha),
            .text => |text| {
                if (!text_pango.draw(self.pixels, width, text.bounds.x, text.bounds.y, @min(text.bounds.width, width -| text.bounds.x), text.value, pack(text.color), text.scale, text.language, text.lines, text.bounds.height)) @panic("Text renderer unavailable");
            },
            .menu_row => |row| self.menuRow(row),
            .battery => |battery| self.drawBattery(battery),
            .cover => |cover| self.drawCover(cover),
            .cartridge => |cartridge| self.drawCartridge(cartridge),
            .overlay_row => |item| self.drawOverlayRow(item),
        };
    }

    fn pack(color: ui.Color) u32 {
        return @bitCast(color);
    }

    fn percent(value: u16, amount: u16) u16 {
        return @intCast((@as(u32, value) * amount) / 100);
    }

    fn fill(self: Surface, rect: ui.Rect, color: ui.Color) void {
        if (rect.x >= width or rect.y >= height) return;
        const right = @min(@as(usize, rect.x) + rect.width, width);
        const bottom = @min(@as(usize, rect.y) + rect.height, height);
        var y: usize = rect.y;
        while (y < bottom) : (y += 1) {
            @memset(self.pixels[y * width + rect.x .. y * width + right], pack(color));
        }
    }

    fn fillAlpha(self: Surface, rect: ui.Rect, color: ui.Color, alpha: u8) void {
        if (rect.x >= width or rect.y >= height) return;
        const right = @min(@as(usize, rect.x) + rect.width, width);
        const bottom = @min(@as(usize, rect.y) + rect.height, height);
        var y: usize = rect.y;
        while (y < bottom) : (y += 1) {
            var x: usize = rect.x;
            while (x < right) : (x += 1) {
                var destination: ui.Color = @bitCast(self.pixels[y * width + x]);
                destination.r = blend255(destination.r, color.r, alpha);
                destination.g = blend255(destination.g, color.g, alpha);
                destination.b = blend255(destination.b, color.b, alpha);
                self.pixels[y * width + x] = pack(destination);
            }
        }
    }

    fn blend255(destination: u8, source: u8, alpha: u8) u8 {
        return @intCast((@as(u32, source) * alpha + @as(u32, destination) * (255 - alpha) + 127) / 255);
    }

    fn menuRow(self: Surface, row: ui.MenuRow) void {
        if (row.selected) {
            self.fill(row.bounds, ui.palette.selected);
            self.fill(.{ .x = row.bounds.x, .y = row.bounds.y, .width = 6, .height = row.bounds.height }, ui.palette.pine);
        } else {
            self.fill(row.bounds, ui.palette.paper);
            self.fill(.{ .x = row.bounds.x, .y = row.bounds.y + row.bounds.height - 1, .width = row.bounds.width, .height = 1 }, ui.palette.chrome);
        }
        const color = if (row.selected) ui.palette.pine else ui.palette.ink;
        const label_y = if (row.detail.len == 0) row.bounds.y + 22 else row.bounds.y + 8;
        self.drawTextBounded(row.bounds.x + 28, label_y, row.bounds.width - 76, row.label, color, 3);
        if (row.detail.len != 0) {
            const detail_color = if (row.selected) ui.palette.pine else ui.palette.quiet;
            self.drawTextBounded(row.bounds.x + 30, row.bounds.y + 57, row.bounds.width - 76, row.detail, detail_color, 2);
        }
        if (row.disclosure) self.drawChevron(row.bounds.x + row.bounds.width - 38, row.bounds.y + 34, color);
    }

    fn drawOverlayRow(self: Surface, item: ui.OverlayRow) void {
        self.fill(item.bounds, if (item.selected) ui.palette.selected else ui.palette.paper);
        if (item.selected) self.fill(.{ .x = item.bounds.x, .y = item.bounds.y, .width = 6, .height = item.bounds.height }, ui.palette.pine);
        const color = if (item.selected) ui.palette.pine else ui.palette.ink;
        const stacked = item.bounds.width < 600 and item.value.len != 0;
        const value_width: u16 = if (item.value.len != 0 and !stacked) @min(320, item.bounds.width / 2) else 0;
        const label_y = item.bounds.y + (if (item.detail.len == 0 and !stacked) @as(u16, 22) else 4);
        self.drawTextBounded(item.bounds.x + 24, label_y, item.bounds.width - value_width - 48, item.label, color, 3);
        if (stacked) self.drawTextBounded(item.bounds.x + 24, item.bounds.y + 50, item.bounds.width - 48, item.value, ui.palette.quiet, 2);
        if (item.detail.len != 0 and !stacked) self.drawTextBounded(item.bounds.x + 24, item.bounds.y + 50, item.bounds.width - 48, item.detail, ui.palette.quiet, 2);
        if (item.value.len != 0 and !stacked) self.drawTextBounded(item.bounds.x + item.bounds.width - value_width, label_y, value_width - 16, item.value, color, 2);
    }

    fn drawTexture(self: Surface, texture: @import("asset_manifest.zig").Texture, bounds: ui.Rect) void {
        self.drawTextureDimmed(texture, bounds, 0, 0, 0);
    }

    fn drawTextureDimmed(self: Surface, texture: @import("asset_manifest.zig").Texture, bounds: ui.Rect, dim: u8, tilt: i16, clip_left: u16) void {
        if (bounds.width == 0 or bounds.height == 0) return;
        var fitted = bounds;
        const fitted_width = @as(u32, bounds.height) * texture.content_width / texture.content_height;
        if (fitted_width <= bounds.width) {
            fitted.width = @intCast(fitted_width);
            fitted.x += (bounds.width - fitted.width) / 2;
        } else {
            fitted.height = @intCast(@as(u32, bounds.width) * texture.content_height / texture.content_width);
            fitted.y += (bounds.height - fitted.height) / 2;
        }
        var y: u16 = 0;
        while (y < fitted.height and fitted.y + y < height) : (y += 1) {
            var x: u16 = 0;
            while (x < fitted.width) : (x += 1) {
                const screen_x = @as(i32, fitted.x) + x - clip_left;
                if (screen_x < 0 or screen_x >= width) continue;
                const far_x = if (tilt < 0) x else fitted.width - 1 - x;
                const inset: u16 = @intCast(@as(u32, far_x) * @abs(tilt) * fitted.height / @max(1, @as(u32, fitted.width) * 8000));
                if (y < inset or y >= fitted.height - inset) continue;
                const source_y = texture.content_y + @as(usize, y - inset) * texture.content_height / (fitted.height - 2 * inset);
                const source_x = texture.content_x + @as(usize, x) * texture.content_width / fitted.width;
                var source: ui.Color = @bitCast(texture.pixels[source_y * texture.width + source_x]);
                if (source.a == 0) continue;
                if (dim != 0) {
                    source.r = blend255(source.r, ui.palette.deep.r, dim);
                    source.g = blend255(source.g, ui.palette.deep.g, dim);
                    source.b = blend255(source.b, ui.palette.deep.b, dim);
                }
                const index = @as(usize, fitted.y + y) * width + @as(usize, @intCast(screen_x));
                if (source.a == 255) {
                    self.pixels[index] = @bitCast(source);
                } else {
                    var destination: ui.Color = @bitCast(self.pixels[index]);
                    destination.r = blend255(destination.r, source.r, source.a);
                    destination.g = blend255(destination.g, source.g, source.a);
                    destination.b = blend255(destination.b, source.b, source.a);
                    self.pixels[index] = @bitCast(destination);
                }
            }
        }
    }

    fn platformIs(value: []const u8, expected: []const u8) bool {
        return std.mem.eql(u8, value, expected);
    }

    fn drawCartridge(self: Surface, cartridge: ui.Cartridge) void {
        const bounds = cartridge.bounds;
        if (cartridge.sprite) |sprite| {
            self.drawTextureDimmed(sprite, bounds, cartridge.dim, cartridge.tilt, cartridge.clip_left);
            return;
        }
        if (cartridge.plain_fallback) {
            self.fill(bounds, ui.palette.surface);
            self.drawTextBounded(bounds.x + 16, bounds.y + bounds.height / 2, bounds.width -| 32, "No artwork", ui.palette.quiet, 2);
            return;
        }
        const ratio: struct { width: u16, height: u16 } = if (platformIs(cartridge.platform, "gba"))
            .{ .width = 15, .height = 9 }
        else if (platformIs(cartridge.platform, "snes"))
            .{ .width = 12, .height = 10 }
        else if (platformIs(cartridge.platform, "megadrive"))
            .{ .width = 10, .height = 12 }
        else if (platformIs(cartridge.platform, "psx"))
            .{ .width = 1, .height = 1 }
        else
            .{ .width = 4, .height = 5 };
        var body_width: u16 = bounds.width;
        var body_height: u16 = @intCast(@as(u32, body_width) * ratio.height / ratio.width);
        if (body_height > bounds.height) {
            body_height = bounds.height;
            body_width = @intCast(@as(u32, body_height) * ratio.width / ratio.height);
        }
        const body = ui.Rect{
            .x = bounds.x + (bounds.width - body_width) / 2,
            .y = bounds.y + (bounds.height - body_height) / 2,
            .width = body_width,
            .height = body_height,
        };
        const shell = if (platformIs(cartridge.platform, "gb"))
            ui.Color{ .r = 0x9b, .g = 0x9a, .b = 0x91 }
        else if (platformIs(cartridge.platform, "gbc"))
            ui.Color{ .r = 0x3b, .g = 0x3d, .b = 0x43 }
        else if (platformIs(cartridge.platform, "gba"))
            ui.Color{ .r = 0x58, .g = 0x5d, .b = 0x64 }
        else if (platformIs(cartridge.platform, "nes"))
            ui.Color{ .r = 0x98, .g = 0x99, .b = 0x95 }
        else if (platformIs(cartridge.platform, "snes"))
            ui.Color{ .r = 0xb8, .g = 0xb8, .b = 0xb2 }
        else if (platformIs(cartridge.platform, "ngpc"))
            ui.Color{ .r = 0x38, .g = 0x3b, .b = 0x3d }
        else
            ui.Color{ .r = 0x24, .g = 0x27, .b = 0x29 };
        self.fill(.{ .x = body.x + 8, .y = body.y + 10, .width = body.width, .height = body.height }, ui.palette.chrome_dark);
        self.fill(body, shell);
        const edge: u16 = if (cartridge.selected) 5 else 2;
        const edge_color = if (cartridge.selected) ui.palette.pine else ui.palette.chrome_dark;
        self.fill(.{ .x = body.x, .y = body.y, .width = body.width, .height = edge }, edge_color);
        self.fill(.{ .x = body.x, .y = body.y + body.height - edge, .width = body.width, .height = edge }, edge_color);
        self.fill(.{ .x = body.x, .y = body.y, .width = edge, .height = body.height }, edge_color);
        self.fill(.{ .x = body.x + body.width - edge, .y = body.y, .width = edge, .height = body.height }, edge_color);
        const label = ui.Rect{
            .x = body.x + body.width / 8,
            .y = body.y + body.height / 6,
            .width = body.width * 3 / 4,
            .height = body.height * 3 / 5,
        };
        self.fill(label, ui.palette.surface);
        if (cartridge.texture) |texture| self.drawTexture(texture, label);
        if (platformIs(cartridge.platform, "gba")) {
            const lip = @max(@as(u16, 4), body.height / 14);
            self.fill(.{ .x = body.x + body.width / 12, .y = body.y, .width = body.width * 5 / 6, .height = lip }, shell);
        }
    }

    fn drawCover(self: Surface, cover: ui.Cover) void {
        const b = cover.bounds;
        self.fill(.{ .x = b.x + 10, .y = b.y + 12, .width = b.width, .height = b.height }, ui.palette.chrome_dark);
        self.fill(b, ui.palette.white);
        const inset: u16 = @max(@as(u16, 6), b.width / 26);
        const inner = ui.Rect{
            .x = b.x + inset,
            .y = b.y + inset,
            .width = b.width - inset * 2,
            .height = b.height - inset * 2,
        };
        switch (cover.kind) {
            .library => {
                self.fill(inner, ui.palette.navy);
                const gap: u16 = @max(@as(u16, 5), inner.width / 30);
                const tile: u16 = (inner.width - gap * 3) / 2;
                self.fill(.{ .x = inner.x + gap, .y = inner.y + gap, .width = tile, .height = tile }, ui.palette.sky);
                self.fill(.{ .x = inner.x + gap * 2 + tile, .y = inner.y + gap, .width = tile, .height = tile }, ui.palette.coral);
                self.fill(.{ .x = inner.x + gap, .y = inner.y + gap * 2 + tile, .width = tile, .height = tile }, ui.palette.gold);
                self.fill(.{ .x = inner.x + gap * 2 + tile, .y = inner.y + gap * 2 + tile, .width = tile, .height = tile }, ui.palette.green);
                const word_scale: u8 = @intCast(@max(@as(u16, 2), b.width / 90));
                self.drawText(inner.x + inner.width / 5, inner.y + inner.height / 2 - 12, "PLAY", ui.palette.white, word_scale);
            },
            .falling => {
                self.fill(inner, ui.palette.sky);
                self.fill(.{ .x = inner.x, .y = inner.y + inner.height * 3 / 4, .width = inner.width, .height = inner.height / 4 }, ui.palette.navy);
                const sun = @max(@as(u16, 18), inner.width / 8);
                self.fill(.{ .x = inner.x + inner.width * 3 / 4, .y = inner.y + inner.height / 7, .width = sun, .height = sun }, ui.palette.gold);
                const hero = @max(@as(u16, 36), inner.width / 4);
                const hx = inner.x + inner.width / 3;
                const hy = inner.y + inner.height / 2;
                self.fill(.{ .x = hx, .y = hy, .width = hero, .height = hero }, ui.palette.coral);
                const eye = @max(@as(u16, 3), hero / 10);
                self.fill(.{ .x = hx + hero / 4, .y = hy + hero / 4, .width = eye, .height = eye }, ui.palette.white);
                self.fill(.{ .x = hx + hero * 2 / 3, .y = hy + hero / 4, .width = eye, .height = eye }, ui.palette.white);
                const word_scale: u8 = @intCast(@max(@as(u16, 2), b.width / 90));
                self.drawText(inner.x + inner.width / 7, inner.y + inner.height / 8, "FALLING", ui.palette.navy, word_scale);
            },
            .minekart => {
                self.fill(inner, ui.palette.navy);
                const rail = @max(@as(u16, 4), inner.width / 50);
                self.fill(.{ .x = inner.x + inner.width / 4, .y = inner.y + inner.height / 2, .width = rail, .height = inner.height / 2 }, ui.palette.gold);
                self.fill(.{ .x = inner.x + inner.width * 3 / 4, .y = inner.y + inner.height / 2, .width = rail, .height = inner.height / 2 }, ui.palette.gold);
                var step: u16 = 0;
                while (step < 5) : (step += 1) {
                    const y = inner.y + inner.height / 2 + step * inner.height / 10;
                    self.fill(.{ .x = inner.x + inner.width / 5, .y = y, .width = inner.width * 3 / 5, .height = rail }, ui.palette.chrome_dark);
                }
                const cart_w = inner.width / 3;
                self.fill(.{ .x = inner.x + inner.width / 2 - cart_w / 2, .y = inner.y + inner.height / 2, .width = cart_w, .height = inner.height / 6 }, ui.palette.coral);
                const word_scale: u8 = @intCast(@max(@as(u16, 2), b.width / 105));
                self.drawText(inner.x + inner.width / 7, inner.y + inner.height / 8, "MINEKART", ui.palette.gold, word_scale);
            },
            .adjustris => {
                self.fill(inner, ui.palette.ink);
                const block = inner.width / 7;
                self.fill(.{ .x = inner.x + block, .y = inner.y + block, .width = block * 2, .height = block }, ui.palette.green);
                self.fill(.{ .x = inner.x + block * 3, .y = inner.y + block * 2, .width = block, .height = block * 3 }, ui.palette.gold);
                self.fill(.{ .x = inner.x + block * 4, .y = inner.y + block * 4, .width = block * 2, .height = block }, ui.palette.coral);
                const word_scale: u8 = @intCast(@max(@as(u16, 2), b.width / 105));
                self.drawText(inner.x + inner.width / 10, inner.y + inner.height * 3 / 4, "ADJUSTRIS", ui.palette.white, word_scale);
            },
            .rkanoid => {
                self.fill(inner, ui.palette.navy);
                const row_h = @max(@as(u16, 6), inner.height / 18);
                const colors = [_]ui.Color{ ui.palette.coral, ui.palette.gold, ui.palette.green, ui.palette.sky };
                for (colors, 0..) |color, row| {
                    self.fill(.{ .x = inner.x + inner.width / 8, .y = inner.y + inner.height / 6 + @as(u16, @intCast(row)) * (row_h + 4), .width = inner.width * 3 / 4, .height = row_h }, color);
                }
                self.fill(.{ .x = inner.x + inner.width / 3, .y = inner.y + inner.height * 4 / 5, .width = inner.width / 3, .height = row_h }, ui.palette.white);
                const word_scale: u8 = @intCast(@max(@as(u16, 2), b.width / 105));
                self.drawText(inner.x + inner.width / 4, inner.y + inner.height / 16, "RKANOID", ui.palette.white, word_scale);
            },
            .willow => {
                self.fill(inner, ui.palette.navy);
                const moon = inner.width / 5;
                self.fill(.{ .x = inner.x + inner.width * 3 / 5, .y = inner.y + inner.height / 8, .width = moon, .height = moon }, ui.palette.gold);
                self.fill(.{ .x = inner.x, .y = inner.y + inner.height * 2 / 3, .width = inner.width, .height = inner.height / 3 }, ui.palette.green);
                const trunk = @max(@as(u16, 6), inner.width / 24);
                self.fill(.{ .x = inner.x + inner.width / 3, .y = inner.y + inner.height / 3, .width = trunk, .height = inner.height / 2 }, ui.palette.chrome_dark);
                self.fill(.{ .x = inner.x + inner.width / 5, .y = inner.y + inner.height / 4, .width = inner.width / 3, .height = inner.height / 4 }, ui.palette.green);
                const word_scale: u8 = @intCast(@max(@as(u16, 2), b.width / 115));
                self.drawText(inner.x + inner.width / 10, inner.y + inner.height / 14, "WILLOWS DREAM", ui.palette.white, word_scale);
            },
        }
    }

    fn drawBattery(self: Surface, battery: ui.Battery) void {
        const body = battery.bounds;
        self.fill(.{ .x = body.x, .y = body.y, .width = body.width - 8, .height = 3 }, ui.palette.ink);
        self.fill(.{ .x = body.x, .y = body.y + body.height - 3, .width = body.width - 8, .height = 3 }, ui.palette.ink);
        self.fill(.{ .x = body.x, .y = body.y, .width = 3, .height = body.height }, ui.palette.ink);
        self.fill(.{ .x = body.x + body.width - 11, .y = body.y, .width = 3, .height = body.height }, ui.palette.ink);
        self.fill(.{ .x = body.x + body.width - 8, .y = body.y + 7, .width = 8, .height = body.height - 14 }, ui.palette.ink);
        const capacity: u16 = body.width - 17;
        const charge: u16 = @intCast((@as(u32, capacity) * battery.percent) / 100);
        self.fill(.{ .x = body.x + 6, .y = body.y + 6, .width = charge, .height = body.height - 12 }, ui.palette.pine);
    }

    fn drawChevron(self: Surface, x: u16, y: u16, color: ui.Color) void {
        var step: u16 = 0;
        while (step < 11) : (step += 1) {
            self.fill(.{ .x = x + step, .y = y + step, .width = 4, .height = 4 }, color);
            self.fill(.{ .x = x + 10 - step, .y = y + 10 + step, .width = 4, .height = 4 }, color);
        }
    }

    fn drawText(self: Surface, x: u16, y: u16, value: []const u8, color: ui.Color, scale: u8) void {
        self.drawTextBounded(x, y, width, value, color, scale);
    }

    fn drawTextBounded(self: Surface, x: u16, y: u16, max_width: u16, value: []const u8, color: ui.Color, scale: u8) void {
        self.drawTextBoundedLanguage(x, y, max_width, value, color, scale, "");
    }

    fn drawTextBoundedLanguage(self: Surface, x: u16, y: u16, max_width: u16, value: []const u8, color: ui.Color, scale: u8, language: []const u8) void {
        if (x >= width or y >= height or scale == 0) return;
        const available = @min(max_width, width - x);
        if (!text_pango.draw(self.pixels, width, x, y, available, value, pack(color), scale, language, 1, 96))
            @panic("PangoFT2 text renderer or required fonts are unavailable");
    }
};

test "long text stays within its bounds and offscreen rectangles are harmless" {
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    @memset(pixels, 0);
    const surface = Surface{ .pixels = pixels };
    surface.fill(.{ .x = 2000, .y = 10, .width = 5, .height = 5 }, ui.palette.white);
    const long_text: [255]u8 = @splat('B');
    surface.drawTextBounded(10, 10, 90, &long_text, ui.palette.white, 3);
    var written: usize = 0;
    for (pixels, 0..) |pixel, index| {
        if (pixel != 0) {
            written += 1;
            try std.testing.expect(index % width >= 10 and index % width < 100);
            try std.testing.expect(index / width >= 10 and index / width < 64);
        }
    }
    try std.testing.expect(written > 0);
}

test "lowercase and uppercase preserve distinct letterforms" {
    const a = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(a);
    const b = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(b);
    @memset(a, 0);
    @memset(b, 0);
    (Surface{ .pixels = a }).drawText(10, 10, "hello pong", ui.palette.white, 3);
    (Surface{ .pixels = b }).drawText(10, 10, "HELLO PONG", ui.palette.white, 3);
    try std.testing.expect(!std.mem.eql(u32, a, b));
    try std.testing.expect(std.mem.count(u32, a, &.{0}) < a.len);
    try std.testing.expect(std.mem.count(u32, b, &.{0}) < b.len);
}

test "multiline titles use their height and remain inside the text rectangle" {
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    @memset(pixels, Surface.pack(ui.palette.paper));
    var tree = ui.Tree{ .background = ui.palette.paper };
    tree.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 40, .width = 400, .height = 120 }, .value = "A long game title that must occupy two lines", .color = ui.palette.ink, .scale = 3, .lines = 2 } });
    (Surface{ .pixels = pixels }).render(&tree);
    var second_line = false;
    for (pixels, 0..) |pixel, index| {
        if (pixel == Surface.pack(ui.palette.paper)) continue;
        const x = index % width;
        const y = index / width;
        try std.testing.expect(x >= 40 and x < 440 and y >= 40 and y < 160);
        if (y >= 90) second_line = true;
    }
    try std.testing.expect(second_line);
}
