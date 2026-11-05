// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const ui = @import("ui.zig");
const text_pango = @import("text_pango.zig");

pub const width = 1024;
pub const height = 768;

pub const Surface = struct {
    pixels: []u32,

    pub fn render(self: Surface, tree: *const ui.Tree) void {
        @memset(self.pixels, pack(tree.background));
        for (tree.slice()) |element| switch (element) {
            .bar => |bar| self.fill(bar.bounds, bar.color),
            .scrim => |scrim| self.fillAlpha(scrim.bounds, scrim.color, scrim.alpha),
            .text => |text| self.drawTextBoundedLanguage(text.bounds.x, text.bounds.y, text.bounds.width, text.value, text.color, text.scale, text.language),
            .menu_row => |row| self.menuRow(row),
            .battery => |battery| self.drawBattery(battery),
            .cover => |cover| self.drawCover(cover),
            .game_scene => |scene| self.drawGameScene(scene),
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

    fn drawGameScene(self: Surface, scene: ui.GameScene) void {
        const b = scene.bounds;
        self.fill(b, ui.palette.navy);
        const horizon = b.y + percent(b.height, 46);
        self.fill(.{ .x = b.x, .y = horizon, .width = b.width, .height = b.height - (horizon - b.y) }, ui.Color{ .r = 0x9e, .g = 0x59, .b = 0x67 });
        const water = b.y + percent(b.height, 72);
        self.fill(.{ .x = b.x, .y = water, .width = b.width, .height = b.height - (water - b.y) }, ui.Color{ .r = 0x18, .g = 0x43, .b = 0x4d });

        const sun = @max(@as(u16, 30), b.width / 10);
        self.fill(.{
            .x = b.x + percent(b.width, 72),
            .y = b.y + percent(b.height, 18),
            .width = sun,
            .height = sun,
        }, ui.palette.gold);

        const mountain_y = b.y + percent(b.height, 54);
        var step: u16 = 0;
        while (step < 7) : (step += 1) {
            const inset = step * b.width / 50;
            self.fill(.{
                .x = b.x + b.width / 12 + inset,
                .y = mountain_y - step * 9,
                .width = percent(b.width, 40) - inset * 2,
                .height = 10,
            }, ui.Color{ .r = 0x21, .g = 0x32, .b = 0x49 });
        }
        step = 0;
        while (step < 7) : (step += 1) {
            const inset = step * b.width / 50;
            self.fill(.{
                .x = b.x + percent(b.width, 48) + inset,
                .y = mountain_y + 20 - step * 9,
                .width = percent(b.width, 44) - inset * 2,
                .height = 10,
            }, ui.Color{ .r = 0x18, .g = 0x28, .b = 0x3d });
        }

        const track_y = b.y + percent(b.height, 80);
        const rail = @max(@as(u16, 3), b.width / 100);
        self.fill(.{ .x = b.x + percent(b.width, 27), .y = track_y, .width = rail, .height = b.height - (track_y - b.y) }, ui.palette.gold);
        self.fill(.{ .x = b.x + percent(b.width, 67), .y = track_y, .width = rail, .height = b.height - (track_y - b.y) }, ui.palette.gold);
        step = 0;
        while (step < 5) : (step += 1) {
            self.fill(.{
                .x = b.x + percent(b.width, 20),
                .y = track_y + step * @max(@as(u16, 9), b.height / 45),
                .width = percent(b.width, 55),
                .height = rail,
            }, ui.palette.chrome_dark);
        }
        self.fill(.{
            .x = b.x + percent(b.width, 41),
            .y = track_y - b.height / 12,
            .width = b.width / 6,
            .height = b.height / 11,
        }, ui.palette.coral);
    }

    fn drawOverlayRow(self: Surface, item: ui.OverlayRow) void {
        const background = if (item.selected) ui.palette.deep else ui.palette.paper;
        self.fill(item.bounds, background);
        if (item.selected) {
            self.fill(.{ .x = item.bounds.x, .y = item.bounds.y, .width = 6, .height = item.bounds.height }, ui.palette.pine);
        } else {
            self.fill(.{ .x = item.bounds.x, .y = item.bounds.y + item.bounds.height - 1, .width = item.bounds.width, .height = 1 }, ui.palette.chrome);
        }
        const label_color = if (item.selected) ui.palette.white else ui.palette.ink;
        const detail_color = if (item.selected) ui.palette.white else ui.palette.quiet;
        const value_scale: u8 = if (item.value.len != 0) 2 else 3;
        const value_step: usize = if (value_scale == 2) 18 else 23;
        const reserved: u16 = if (item.value.len != 0) @intCast(@as(usize, @min(item.value.len, 18)) * value_step + 28) else if (item.disclosure) 70 else 28;
        const label_y = if (item.detail.len == 0) item.bounds.y + 16 else item.bounds.y + 4;
        self.drawTextBounded(item.bounds.x + 28, label_y, item.bounds.width - 28 - reserved, item.label, label_color, value_scale);
        if (item.detail.len != 0)
            self.drawTextBounded(item.bounds.x + 30, item.bounds.y + 48, item.bounds.width - 60, item.detail, detail_color, 2);
        if (item.value.len != 0) {
            const value_width: u16 = @intCast(@min(item.value.len * value_step, item.bounds.width / 2));
            const right_padding: u16 = if (item.disclosure) 70 else 28;
            self.drawText(item.bounds.x + item.bounds.width - right_padding - value_width, label_y, item.value, label_color, value_scale);
        }
        if (item.disclosure)
            self.drawChevron(item.bounds.x + item.bounds.width - 40, item.bounds.y + 30, label_color);
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
        if (!text_pango.draw(self.pixels, width, x, y, available, value, pack(color), scale, language))
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
