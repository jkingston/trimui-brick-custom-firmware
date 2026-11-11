// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const design = @import("design.zig");
const font = design.typeface;
const geometry = design.geometry;
const artwork_colors = @import("artwork_colors.zig");
const damage = @import("damage.zig");
const ui = @import("ui_scene.zig");
const text_pango = @import("text_pango.zig");

pub const width: usize = design.geometry.width;
pub const height: usize = design.geometry.height;

pub fn prepareText(tree: *const ui.Tree) void {
    var token: u8 = 0;
    (Surface{ .sink = .{ .context = &token, .clip = Preparation.clip, .fill = Preparation.fill, .mask = Preparation.mask, .texture = Preparation.texture } }).render(tree);
}

const Preparation = struct {
    fn clip(_: *anyopaque, _: []const ui.Rect) void {}
    fn fill(_: *anyopaque, _: ui.Rect, _: ui.Color, _: u8) void {}
    fn mask(_: *anyopaque, _: u64, _: u16, _: u16, _: []const u8, _: u16, _: u16, _: u32) void {}
    fn texture(_: *anyopaque, _: @import("asset_manifest.zig").Texture, _: ui.Rect, _: u8, _: i16, _: u16) void {}
};

test "text preparation warms the next paint without changing its tree" {
    const views = @import("ui.zig");
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    var tree = views.wifiPassword(@import("theme.zig").light, "Example", .{ .selected = 17 }, "", false);
    const before = damage.Scene.capture(&tree);
    prepareText(&tree);
    const misses = text_pango.cacheMissCount();
    (Surface{ .pixels = pixels }).render(&tree);
    try std.testing.expectEqual(misses, text_pango.cacheMissCount());
    const after = damage.Scene.capture(&tree);
    const changes = damage.Scene.changes(&before, &after);
    try std.testing.expectEqual(@as(usize, 0), changes.slice().len);
}

pub const Surface = struct {
    pixels: []u32 = &.{},
    sink: ?@import("paint_sink.zig").Sink = null,
    clips: []const ui.Rect = &.{},
    prepainted_interactions: bool = false,

    pub fn render(self: Surface, tree: *const ui.Tree) void {
        if (!tree.preserve_background) self.fill(.{ .x = 0, .y = 0, .width = width, .height = height }, tree.background);
        var surface = self;
        for (tree.slice()) |element| surface.renderInteractionBackdrop(element);
        surface.prepainted_interactions = true;
        for (tree.slice()) |element| surface.renderElement(element, tree.theme);
    }

    pub fn renderTransition(self: Surface, frame: @import("navigation_motion.zig").Frame) void {
        self.render(frame.base);
        const distance: u16 = @intCast(@abs(frame.offset_x));
        const screen_width: u16 = width;
        const screen_height: u16 = height;
        const visible = if (frame.offset_x > 0)
            ui.Rect{ .x = distance, .y = 0, .width = screen_width -| distance, .height = screen_height }
        else
            ui.Rect{ .x = 0, .y = 0, .width = screen_width -| distance, .height = screen_height };
        var destination = frame.overlay.*;
        destination.preserve_background = true;
        destination.translateX(frame.offset_x);
        var clip = [_]ui.Rect{visible};
        var overlay = self;
        overlay.clips = &clip;
        if (overlay.sink) |sink| sink.clip(sink.context, &clip);
        defer if (overlay.sink) |sink| sink.clip(sink.context, &.{});
        overlay.fill(visible, destination.background);
        overlay.render(&destination);
    }

    pub fn renderDamage(self: Surface, tree: *const ui.Tree, changed: *const damage.RectSet) void {
        const rects = changed.slice();
        if (rects.len == 0) return;
        var surface = self;
        surface.clips = rects;
        if (self.sink) |sink| sink.clip(sink.context, rects);
        defer if (self.sink) |sink| sink.clip(sink.context, &.{});
        if (!tree.preserve_background) for (rects) |rect| {
            if (!opaqueCover(tree, rect)) surface.fill(rect, tree.background);
        };
        for (tree.slice()) |element|
            if (intersectsDamage(element, rects)) surface.renderInteractionBackdrop(element);
        surface.prepainted_interactions = true;
        for (tree.slice()) |element| {
            const bounds = damage.paintBounds(element);
            for (rects) |rect| if (damage.intersects(bounds, rect)) {
                surface.renderElement(element, tree.theme);
                break;
            };
        }
    }

    fn intersectsDamage(element: ui.Element, rects: []const ui.Rect) bool {
        const bounds = damage.paintBounds(element);
        for (rects) |rect| if (damage.intersects(bounds, rect)) return true;
        return false;
    }

    fn opaqueCover(tree: *const ui.Tree, rect: ui.Rect) bool {
        for (tree.slice()) |element| {
            const bounds = switch (element) {
                .bar => |bar| if (bar.radius == 0) bar.bounds else continue,
                .menu_row => |row| if (geometry.radius == 0) row.bounds else continue,
                .action_card => |card| if (geometry.radius == 0) card.bounds else continue,
                .overlay_row => |row| if (geometry.radius == 0) row.bounds else continue,
                else => continue,
            };
            if (contains(bounds, rect)) return true;
        }
        return false;
    }

    fn contains(outer: ui.Rect, inner: ui.Rect) bool {
        return outer.x <= inner.x and outer.y <= inner.y and
            @as(u32, outer.x) + outer.width >= @as(u32, inner.x) + inner.width and
            @as(u32, outer.y) + outer.height >= @as(u32, inner.y) + inner.height;
    }

    pub fn renderElement(self: Surface, element: ui.Element, theme: ui.Theme) void {
        switch (element) {
            .bar => |bar| self.fillRounded(bar.bounds, bar.color, bar.radius),
            .scrim => |scrim| self.fillAlpha(scrim.bounds, scrim.color, scrim.alpha),
            .text => |text| {
                if (!self.paintText(text.bounds.x, text.bounds.y, @min(text.bounds.width, width -| text.bounds.x), text.value, pack(text.color), text.font, text.language, text.lines, text.bounds.height, null, false, 0)) @panic("Text renderer unavailable");
            },
            .text_block => |block| self.textBlock(block),
            .focus_frame => |frame| self.focusFrame(frame),
            .menu_row => |row| self.menuRow(row),
            .action_card => |card| self.actionCard(card),
            .battery => |battery| self.drawBattery(battery),
            .meter => |meter| self.drawMeter(meter),
            .activity => |activity| self.drawActivity(activity),
            .qr_code => |qr| self.drawQr(qr),
            .keyboard => |keyboard| self.drawKeyboard(keyboard, theme),
            .keyboard_key => |key| self.drawKeyboardKey(key.keyboard, theme, key.index, true, false, 0, 0),
            .cover => |cover| self.drawCover(cover),
            .cartridge => |cartridge| self.drawCartridge(cartridge),
            .overlay_row => |item| self.drawOverlayRow(item),
        }
    }

    fn renderInteractionBackdrop(self: Surface, element: ui.Element) void {
        switch (element) {
            .focus_frame => |frame| switch (frame.presentation) {
                .plate => self.interactionPlate(frame.bounds, frame.displayedBounds(), frame.state, frame.style.base, frame.style.background, frame.style.border, frame.style.shadow),
                .quiet => switch (frame.state) {
                    .idle, .disabled => {},
                    .pressed, .activating => self.interactionPlate(frame.bounds, frame.displayedBounds(), frame.state, frame.style.base, frame.style.background, frame.style.border, frame.style.shadow),
                    .focused, .busy, .succeeded, .failed, .boundary => self.interactionField(frame.displayedBounds(), frame.state, frame.style.background, frame.style.border),
                },
            },
            .menu_row => |row| self.interactionPlate(row.bounds, row.displayedBounds(), row.state, row.style.base, row.style.background, row.style.border, row.style.shadow),
            .action_card => |card| self.interactionPlate(card.bounds, card.displayedBounds(), card.state, card.style.base, card.style.background, card.style.border, card.style.shadow),
            .overlay_row => |row| self.interactionPlate(row.bounds, row.displayedBounds(), row.state, row.style.base, row.style.background, row.style.border, row.style.shadow),
            else => {},
        }
    }

    fn interactionPlate(self: Surface, logical: ui.Rect, displayed: ui.Rect, state: @import("interaction.zig").State, base: ui.Color, background: ui.Color, border: ui.Color, shadow: ui.Color) void {
        self.fillRounded(logical, base, geometry.radius);
        if (!state.hasFocus()) return;
        const pressed = state == .pressed or state == .activating;
        const plate = if (pressed) contract(logical, if (state == .pressed) 2 else 1) else displayed;
        if (!pressed) {
            const shadow_bounds = ui.Rect{ .x = plate.x, .y = @min(@as(u16, @intCast(height)) - plate.height, plate.y + 3), .width = plate.width, .height = plate.height };
            self.fillRounded(shadow_bounds, shadow, geometry.radius);
        }
        self.fillRounded(plate, background, geometry.radius);
        self.stroke(plate, border, if (state == .boundary or state == .failed) 3 else 1);
    }

    /// Editorial focus is a quiet change in local luminance, not a card or
    /// selection ornament. Its geometry is still animated by focus_motion, so
    /// direction remains perceptible without moving or reflowing the label.
    fn interactionField(self: Surface, bounds: ui.Rect, state: @import("interaction.zig").State, background: ui.Color, signal: ui.Color) void {
        const strengths = [_]u8{ 28, 104, 176, 146, 108, 72, 38, 12 };
        const band_count: u16 = @intCast(strengths.len);
        const band_width = @max(@as(u16, 1), @divTrunc(bounds.width + band_count - 1, band_count));
        for (strengths, 0..) |strength, index| {
            const x = bounds.x +| (@as(u16, @intCast(index)) *| band_width);
            const width_remaining = (bounds.x +| bounds.width) -| x;
            if (width_remaining == 0) break;
            const width_band = @min(band_width, width_remaining);
            const vertical_fade = @min(@as(u16, 6), bounds.height / 3);
            self.fillAlpha(.{ .x = x, .y = bounds.y, .width = width_band, .height = vertical_fade }, background, strength / 3);
            self.fillAlpha(.{ .x = x, .y = bounds.y +| vertical_fade, .width = width_band, .height = bounds.height -| (2 *| vertical_fade) }, background, strength);
            self.fillAlpha(.{ .x = x, .y = (bounds.y +| bounds.height) -| vertical_fade, .width = width_band, .height = vertical_fade }, background, strength / 3);
        }
        if (state == .boundary or state == .failed) self.stroke(bounds, signal, 3);
    }

    fn contract(bounds: ui.Rect, amount: u16) ui.Rect {
        const safe = @min(amount, @min(bounds.width / 2, bounds.height / 2));
        return .{ .x = bounds.x + safe, .y = bounds.y + safe, .width = bounds.width - 2 * safe, .height = bounds.height - 2 * safe };
    }

    fn artworkFont(size: u16) design.Font {
        return switch (@max(2, size)) {
            2 => font.caption,
            3 => font.body,
            4 => font.title,
            else => font.brand,
        };
    }

    fn pack(color: ui.Color) u32 {
        return @bitCast(color);
    }

    fn percent(value: u16, amount: u16) u16 {
        return @intCast((@as(u32, value) * amount) / 100);
    }

    fn fill(self: Surface, rect: ui.Rect, color: ui.Color) void {
        if (self.sink) |sink| return sink.fill(sink.context, rect, color, 255);
        if (self.clips.len != 0) {
            var unclipped = self;
            unclipped.clips = &.{};
            for (self.clips) |clip| if (damage.intersection(rect, clip)) |part| unclipped.fill(part, color);
            return;
        }
        if (rect.x >= width or rect.y >= height) return;
        const right = @min(@as(usize, rect.x) + rect.width, width);
        const bottom = @min(@as(usize, rect.y) + rect.height, height);
        var y: usize = rect.y;
        while (y < bottom) : (y += 1) {
            @memset(self.pixels[y * width + rect.x .. y * width + right], pack(color));
        }
    }

    fn fillRounded(self: Surface, rect: ui.Rect, color: ui.Color, requested_radius: u16) void {
        const radius = @min(requested_radius, @min(rect.width / 2, rect.height / 2));
        if (radius == 0) return self.fill(rect, color);
        self.fill(.{ .x = rect.x, .y = rect.y + radius, .width = rect.width, .height = rect.height - 2 * radius }, color);
        for (0..radius) |row| {
            const dy = radius - @as(u16, @intCast(row)) - 1;
            var inset: u16 = 0;
            while ((radius - inset) * (radius - inset) + dy * dy > radius * radius) inset += 1;
            self.fill(.{ .x = rect.x + inset, .y = rect.y + @as(u16, @intCast(row)), .width = rect.width - 2 * inset, .height = 1 }, color);
            self.fill(.{ .x = rect.x + inset, .y = rect.y + rect.height - 1 - @as(u16, @intCast(row)), .width = rect.width - 2 * inset, .height = 1 }, color);
        }
    }

    fn fillAlpha(self: Surface, rect: ui.Rect, color: ui.Color, alpha: u8) void {
        if (self.sink) |sink| return sink.fill(sink.context, rect, color, alpha);
        if (rect.x >= width or rect.y >= height) return;
        const right = @min(@as(usize, rect.x) + rect.width, width);
        const bottom = @min(@as(usize, rect.y) + rect.height, height);
        var y: usize = rect.y;
        while (y < bottom) : (y += 1) {
            var x: usize = rect.x;
            while (x < right) : (x += 1) {
                if (!damage.containsPixel(self.clips, x, y)) continue;
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

    fn textBlock(self: Surface, block: ui.TextBlock) void {
        const tail = block.detail_font.line_height * block.detail_lines + block.gap;
        var measured: u16 = 0;
        const lead: u16 = if (block.detail_above) tail else 0;
        if (!self.paintText(block.bounds.x, block.bounds.y + lead, block.bounds.width, block.title, pack(block.color), block.title_font, "", block.lines, block.bounds.height, &measured, block.centered, tail)) @panic("Text renderer unavailable");
        const top = block.bounds.y + if (block.centered) (block.bounds.height -| (measured + tail)) / 2 else @as(u16, 0);
        const detail_y = if (block.detail_above) top else top + measured + block.gap;
        if (!self.paintText(block.bounds.x, detail_y, block.bounds.width, block.detail, pack(block.detail_color), block.detail_font, "", block.detail_lines, block.detail_font.line_height * block.detail_lines, null, false, 0)) @panic("Text renderer unavailable");
    }

    fn focusFrame(self: Surface, frame: ui.FocusFrame) void {
        if (!self.prepainted_interactions) self.renderInteractionBackdrop(.{ .focus_frame = frame });
    }

    fn menuRow(self: Surface, row: ui.MenuRow) void {
        if (!self.prepainted_interactions) self.renderInteractionBackdrop(.{ .menu_row = row });
        var title_font = row.label_font;
        title_font.ink_centered = true;
        var detail_font = font.caption;
        detail_font.ink_centered = true;
        title_font.weight = if (row.selected) .medium else .regular;
        if (row.lines == 2) title_font.line_height = 44;
        const padding = geometry.row_padding;
        const available = row.bounds.width - 2 * padding - (if (row.disclosure) @as(u16, 24) else 0) - ui.stateAffordanceWidth(row.state);
        const tail: u16 = if (row.detail.len != 0) font.caption.line_height + 6 else 0;
        var measured_height: u16 = 0;
        if (!self.paintText(row.bounds.x + padding, row.bounds.y, available, row.label, pack(row.style.text), title_font, "", row.lines, row.bounds.height, &measured_height, true, tail)) @panic("Text renderer unavailable");
        const text_y = row.bounds.y + (row.bounds.height -| (measured_height + tail)) / 2;
        if (row.detail.len != 0) self.drawTextBounded(row.bounds.x + padding, text_y + measured_height + 6, available, row.detail, row.style.detail, detail_font);
        self.stateAffordance(row.bounds, row.state, row.style.accent, row.activity_phase, row.activity_animated, row.disclosure);
        if (row.disclosure) self.drawChevron(row.bounds.x + row.bounds.width - 38, row.bounds.y + (row.bounds.height - 24) / 2, row.style.text);
    }

    fn actionCard(self: Surface, card: ui.ActionCard) void {
        if (!self.prepainted_interactions) self.renderInteractionBackdrop(.{ .action_card = card });
        const padding: u16 = 28;
        var eyebrow_font = font.control;
        eyebrow_font.size = 25;
        eyebrow_font.line_height = 32;
        eyebrow_font.weight = .semibold;
        var label_font = font.title;
        label_font.size = if (card.emphasis == .primary) 58 else 45;
        label_font.line_height = if (card.emphasis == .primary) 66 else 54;
        var detail_font = font.caption;
        detail_font.size = 29;
        detail_font.line_height = 38;

        const content_width = card.bounds.width - 2 * padding - ui.stateAffordanceWidth(card.state);
        self.drawTextBounded(card.bounds.x + padding, card.bounds.y + padding, content_width, card.eyebrow, card.style.detail, eyebrow_font);

        const detail_height = if (card.detail.len == 0) @as(u16, 0) else detail_font.line_height * card.detail_lines;
        const detail_gap: u16 = if (card.detail.len == 0) 0 else 10;
        const label_height = label_font.line_height * card.label_lines;
        const stack_height = label_height + detail_gap + detail_height;
        const label_y = card.bounds.y + card.bounds.height - padding -| stack_height;
        if (!self.paintText(card.bounds.x + padding, label_y, content_width, card.label, pack(card.style.text), label_font, "", card.label_lines, label_height, null, false, 0)) @panic("Text renderer unavailable");
        if (card.detail.len != 0 and !self.paintText(card.bounds.x + padding, label_y + label_height + detail_gap, content_width, card.detail, pack(card.style.detail), detail_font, "", card.detail_lines, detail_height, null, false, 0)) @panic("Text renderer unavailable");
        self.stateAffordance(card.bounds, card.state, card.style.accent, card.activity_phase, card.activity_animated, false);
    }

    fn drawOverlayRow(self: Surface, item: ui.OverlayRow) void {
        if (!self.prepainted_interactions) self.renderInteractionBackdrop(.{ .overlay_row = item });
        for (@import("row_layout.zig").overlay(item)) |part|
            self.drawTextBounded(part.bounds.x, part.bounds.y, part.bounds.width, part.value, part.color, part.font);
        self.stateAffordance(item.bounds, item.state, item.style.accent, item.activity_phase, item.activity_animated, item.disclosure);
        if (item.disclosure)
            self.drawChevron(item.bounds.x + item.bounds.width - 38, item.bounds.y + (item.bounds.height - 24) / 2, item.style.text);
    }

    fn stateAffordance(self: Surface, bounds: ui.Rect, state: @import("interaction.zig").State, color: ui.Color, phase: u16, animated: bool, disclosure: bool) void {
        if (ui.stateAffordanceWidth(state) == 0) return;
        const disclosure_width: u16 = if (disclosure) 38 else 0;
        const area = ui.Rect{
            .x = bounds.x + bounds.width - geometry.row_padding - disclosure_width - 48,
            .y = bounds.y + (bounds.height - 32) / 2,
            .width = 48,
            .height = 32,
        };
        switch (state) {
            .busy => self.drawActivity(.{ .bounds = area, .color = color, .phase = phase, .animated = animated }),
            .succeeded, .failed => {
                var status_font = font.control;
                status_font.alignment = .center;
                status_font.ink_centered = true;
                self.drawTextBounded(area.x, area.y, area.width, if (state == .succeeded) "✓" else "!", color, status_font);
            },
            else => {},
        }
    }

    fn stroke(self: Surface, bounds: ui.Rect, color: ui.Color, thickness: u16) void {
        const edge = @min(thickness, @min(bounds.width / 2, bounds.height / 2));
        self.fill(.{ .x = bounds.x, .y = bounds.y, .width = bounds.width, .height = edge }, color);
        self.fill(.{ .x = bounds.x, .y = bounds.y + bounds.height - edge, .width = bounds.width, .height = edge }, color);
        self.fill(.{ .x = bounds.x, .y = bounds.y, .width = edge, .height = bounds.height }, color);
        self.fill(.{ .x = bounds.x + bounds.width - edge, .y = bounds.y, .width = edge, .height = bounds.height }, color);
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
        if (self.sink) |sink| return sink.texture(sink.context, texture, fitted, dim, tilt, clip_left);
        var y: u16 = 0;
        while (y < fitted.height and fitted.y + y < height) : (y += 1) {
            var x: u16 = 0;
            while (x < fitted.width) : (x += 1) {
                const screen_x = @as(i32, fitted.x) + x - clip_left;
                if (screen_x < 0 or screen_x >= width) continue;
                if (!damage.containsPixel(self.clips, @intCast(screen_x), fitted.y + y)) continue;
                const far_x = if (tilt < 0) x else fitted.width - 1 - x;
                const inset: u16 = @intCast(@as(u32, far_x) * @abs(tilt) * fitted.height / @max(1, @as(u32, fitted.width) * 8000));
                if (y < inset or y >= fitted.height - inset) continue;
                const source_y = texture.content_y + @as(usize, y - inset) * texture.content_height / (fitted.height - 2 * inset);
                const source_x = texture.content_x + @as(usize, x) * texture.content_width / fitted.width;
                var source: ui.Color = @bitCast(texture.pixels[source_y * texture.width + source_x]);
                if (source.a == 0) continue;
                if (dim != 0) {
                    source.r = blend255(source.r, artwork_colors.deep.r, dim);
                    source.g = blend255(source.g, artwork_colors.deep.g, dim);
                    source.b = blend255(source.b, artwork_colors.deep.b, dim);
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
        const bounds = cartridge.displayBounds();
        if (cartridge.sprite) |sprite| {
            self.drawTextureDimmed(sprite, bounds, cartridge.dim, cartridge.tilt, cartridge.clip_left);
            if (cartridge.selected) self.stroke(bounds, cartridge.style.edge, if (cartridge.state == .pressed or cartridge.state == .boundary) 6 else 4);
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
        self.fill(.{ .x = body.x + 8, .y = body.y + 10, .width = body.width, .height = body.height }, cartridge.style.shadow);
        self.fill(body, shell);
        const edge: u16 = if (cartridge.state == .pressed) 8 else if (cartridge.state == .boundary) 7 else if (cartridge.selected) 5 else 2;
        const edge_color = cartridge.style.edge;
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
        self.fill(label, cartridge.style.surface);
        if (cartridge.texture) |texture| self.drawTexture(texture, label);
        if (platformIs(cartridge.platform, "gba")) {
            const lip = @max(@as(u16, 4), body.height / 14);
            self.fill(.{ .x = body.x + body.width / 12, .y = body.y, .width = body.width * 5 / 6, .height = lip }, shell);
        }
    }

    fn drawCover(self: Surface, cover: ui.Cover) void {
        const b = cover.bounds;
        self.fill(.{ .x = b.x + 10, .y = b.y + 12, .width = b.width, .height = b.height }, artwork_colors.chrome_dark);
        self.fill(b, artwork_colors.white);
        const inset: u16 = @max(@as(u16, 6), b.width / 26);
        const inner = ui.Rect{
            .x = b.x + inset,
            .y = b.y + inset,
            .width = b.width - inset * 2,
            .height = b.height - inset * 2,
        };
        switch (cover.kind) {
            .library => {
                self.fill(inner, artwork_colors.navy);
                const gap: u16 = @max(@as(u16, 5), inner.width / 30);
                const tile: u16 = (inner.width - gap * 3) / 2;
                self.fill(.{ .x = inner.x + gap, .y = inner.y + gap, .width = tile, .height = tile }, artwork_colors.sky);
                self.fill(.{ .x = inner.x + gap * 2 + tile, .y = inner.y + gap, .width = tile, .height = tile }, artwork_colors.coral);
                self.fill(.{ .x = inner.x + gap, .y = inner.y + gap * 2 + tile, .width = tile, .height = tile }, artwork_colors.gold);
                self.fill(.{ .x = inner.x + gap * 2 + tile, .y = inner.y + gap * 2 + tile, .width = tile, .height = tile }, artwork_colors.green);
                const word_font = artworkFont(b.width / 90);
                self.drawText(inner.x + inner.width / 5, inner.y + inner.height / 2 - 12, "PLAY", artwork_colors.white, word_font);
            },
            .falling => {
                self.fill(inner, artwork_colors.sky);
                self.fill(.{ .x = inner.x, .y = inner.y + inner.height * 3 / 4, .width = inner.width, .height = inner.height / 4 }, artwork_colors.navy);
                const sun = @max(@as(u16, 18), inner.width / 8);
                self.fill(.{ .x = inner.x + inner.width * 3 / 4, .y = inner.y + inner.height / 7, .width = sun, .height = sun }, artwork_colors.gold);
                const hero = @max(@as(u16, 36), inner.width / 4);
                const hx = inner.x + inner.width / 3;
                const hy = inner.y + inner.height / 2;
                self.fill(.{ .x = hx, .y = hy, .width = hero, .height = hero }, artwork_colors.coral);
                const eye = @max(@as(u16, 3), hero / 10);
                self.fill(.{ .x = hx + hero / 4, .y = hy + hero / 4, .width = eye, .height = eye }, artwork_colors.white);
                self.fill(.{ .x = hx + hero * 2 / 3, .y = hy + hero / 4, .width = eye, .height = eye }, artwork_colors.white);
                const word_font = artworkFont(b.width / 90);
                self.drawText(inner.x + inner.width / 7, inner.y + inner.height / 8, "FALLING", artwork_colors.navy, word_font);
            },
            .minekart => {
                self.fill(inner, artwork_colors.navy);
                const rail = @max(@as(u16, 4), inner.width / 50);
                self.fill(.{ .x = inner.x + inner.width / 4, .y = inner.y + inner.height / 2, .width = rail, .height = inner.height / 2 }, artwork_colors.gold);
                self.fill(.{ .x = inner.x + inner.width * 3 / 4, .y = inner.y + inner.height / 2, .width = rail, .height = inner.height / 2 }, artwork_colors.gold);
                var step: u16 = 0;
                while (step < 5) : (step += 1) {
                    const y = inner.y + inner.height / 2 + step * inner.height / 10;
                    self.fill(.{ .x = inner.x + inner.width / 5, .y = y, .width = inner.width * 3 / 5, .height = rail }, artwork_colors.chrome_dark);
                }
                const cart_w = inner.width / 3;
                self.fill(.{ .x = inner.x + inner.width / 2 - cart_w / 2, .y = inner.y + inner.height / 2, .width = cart_w, .height = inner.height / 6 }, artwork_colors.coral);
                const word_font = artworkFont(b.width / 105);
                self.drawText(inner.x + inner.width / 7, inner.y + inner.height / 8, "MINEKART", artwork_colors.gold, word_font);
            },
            .adjustris => {
                self.fill(inner, artwork_colors.ink);
                const block = inner.width / 7;
                self.fill(.{ .x = inner.x + block, .y = inner.y + block, .width = block * 2, .height = block }, artwork_colors.green);
                self.fill(.{ .x = inner.x + block * 3, .y = inner.y + block * 2, .width = block, .height = block * 3 }, artwork_colors.gold);
                self.fill(.{ .x = inner.x + block * 4, .y = inner.y + block * 4, .width = block * 2, .height = block }, artwork_colors.coral);
                const word_font = artworkFont(b.width / 105);
                self.drawText(inner.x + inner.width / 10, inner.y + inner.height * 3 / 4, "ADJUSTRIS", artwork_colors.white, word_font);
            },
            .rkanoid => {
                self.fill(inner, artwork_colors.navy);
                const row_h = @max(@as(u16, 6), inner.height / 18);
                const colors = [_]ui.Color{ artwork_colors.coral, artwork_colors.gold, artwork_colors.green, artwork_colors.sky };
                for (colors, 0..) |color, row| {
                    self.fill(.{ .x = inner.x + inner.width / 8, .y = inner.y + inner.height / 6 + @as(u16, @intCast(row)) * (row_h + 4), .width = inner.width * 3 / 4, .height = row_h }, color);
                }
                self.fill(.{ .x = inner.x + inner.width / 3, .y = inner.y + inner.height * 4 / 5, .width = inner.width / 3, .height = row_h }, artwork_colors.white);
                const word_font = artworkFont(b.width / 105);
                self.drawText(inner.x + inner.width / 4, inner.y + inner.height / 16, "RKANOID", artwork_colors.white, word_font);
            },
            .willow => {
                self.fill(inner, artwork_colors.navy);
                const moon = inner.width / 5;
                self.fill(.{ .x = inner.x + inner.width * 3 / 5, .y = inner.y + inner.height / 8, .width = moon, .height = moon }, artwork_colors.gold);
                self.fill(.{ .x = inner.x, .y = inner.y + inner.height * 2 / 3, .width = inner.width, .height = inner.height / 3 }, artwork_colors.green);
                const trunk = @max(@as(u16, 6), inner.width / 24);
                self.fill(.{ .x = inner.x + inner.width / 3, .y = inner.y + inner.height / 3, .width = trunk, .height = inner.height / 2 }, artwork_colors.chrome_dark);
                self.fill(.{ .x = inner.x + inner.width / 5, .y = inner.y + inner.height / 4, .width = inner.width / 3, .height = inner.height / 4 }, artwork_colors.green);
                const word_font = artworkFont(b.width / 115);
                self.drawText(inner.x + inner.width / 10, inner.y + inner.height / 14, "WILLOWS DREAM", artwork_colors.white, word_font);
            },
        }
    }

    fn drawBattery(self: Surface, battery: ui.Battery) void {
        const body = battery.bounds;
        self.fill(.{ .x = body.x, .y = body.y, .width = body.width - 8, .height = 3 }, battery.outline);
        self.fill(.{ .x = body.x, .y = body.y + body.height - 3, .width = body.width - 8, .height = 3 }, battery.outline);
        self.fill(.{ .x = body.x, .y = body.y, .width = 3, .height = body.height }, battery.outline);
        self.fill(.{ .x = body.x + body.width - 11, .y = body.y, .width = 3, .height = body.height }, battery.outline);
        self.fill(.{ .x = body.x + body.width - 8, .y = body.y + 7, .width = 8, .height = body.height - 14 }, battery.outline);
        const capacity: u16 = body.width - 17;
        const charge: u16 = @intCast((@as(u32, capacity) * battery.percent) / 100);
        self.fill(.{ .x = body.x + 6, .y = body.y + 6, .width = charge, .height = body.height - 12 }, battery.charge);
    }

    fn drawMeter(self: Surface, meter: ui.Meter) void {
        if (meter.presentation == .stepped and meter.steps >= 2) {
            const count: u16 = meter.steps;
            const gap: u16 = 8;
            const total_gap = gap * (count - 1);
            if (meter.bounds.width <= total_gap) return;
            const segment_width = (meter.bounds.width - total_gap) / count;
            const value = @min(1000, meter.value);
            const current: u16 = @intCast((@as(u32, value) * (count - 1) + 500) / 1000);
            for (0..count) |index_usize| {
                const index: u16 = @intCast(index_usize);
                const selected = index == current;
                const segment_height: u16 = if (selected) @min(28, meter.bounds.height) else @min(8, meter.bounds.height);
                const color = if (selected) meter.thumb else if (index < current) meter.fill else meter.track;
                self.fillRounded(.{
                    .x = meter.bounds.x + index * (segment_width + gap),
                    .y = meter.bounds.y + (meter.bounds.height - segment_height) / 2,
                    .width = segment_width,
                    .height = segment_height,
                }, color, @min(4, segment_height / 2));
            }
            return;
        }
        const track_height: u16 = @min(12, meter.bounds.height);
        const thumb_size: u16 = @min(30, meter.bounds.height);
        const track = ui.Rect{ .x = meter.bounds.x + thumb_size / 2, .y = meter.bounds.y + (meter.bounds.height - track_height) / 2, .width = meter.bounds.width - thumb_size, .height = track_height };
        self.fillRounded(track, meter.track, track_height / 2);
        const value = @min(1000, meter.value);
        if (value != 0) {
            const filled = @max(track_height, @as(u16, @intCast(@as(u32, track.width) * value / 1000)));
            self.fillRounded(.{ .x = track.x, .y = track.y, .width = filled, .height = track.height }, meter.fill, track_height / 2);
        }
        const center = track.x + @as(u16, @intCast(@as(u32, track.width) * value / 1000));
        const thumb = ui.Rect{ .x = center - thumb_size / 2, .y = meter.bounds.y + (meter.bounds.height - thumb_size) / 2, .width = thumb_size, .height = thumb_size };
        self.fillRounded(thumb, meter.thumb, thumb_size / 2);
        const inset: u16 = 9;
        self.fillRounded(.{ .x = thumb.x + inset, .y = thumb.y + inset, .width = thumb.width - 2 * inset, .height = thumb.height - 2 * inset }, meter.track, (thumb_size - 2 * inset) / 2);
    }

    fn drawActivity(self: Surface, activity: ui.Activity) void {
        const dot: u16 = @min(10, @min(activity.bounds.height, activity.bounds.width / 3));
        if (dot == 0) return;
        const resting_size: u16 = @min(8, dot);
        const gap: u16 = (activity.bounds.width -| 3 * dot) / 2;
        for (0..3) |index| {
            const strength: u16 = if (!activity.animated)
                500
            else blk: {
                const center: i32 = @intCast(index * 333);
                const raw = @abs(@as(i32, activity.phase) - center);
                const distance = @min(raw, 1000 - raw);
                break :blk @intCast(1000 - @min(1000, distance * 3));
            };
            const size: u16 = resting_size + @as(u16, @intCast(@as(u32, strength) * (dot - resting_size) / 1000));
            const slot_x = activity.bounds.x + @as(u16, @intCast(index)) * (dot + gap);
            const bounds = ui.Rect{ .x = slot_x + (dot - size) / 2, .y = activity.bounds.y + (activity.bounds.height - size) / 2, .width = size, .height = size };
            self.fillRounded(bounds, activity.color, size / 2);
        }
    }

    fn drawQr(self: Surface, qr: ui.QrCode) void {
        if (qr.width == 0) return;
        self.fill(qr.bounds, qr.background);
        const scale = @min(qr.bounds.width / qr.width, qr.bounds.height / qr.width);
        if (scale == 0) return;
        const size = scale * qr.width;
        const left = qr.bounds.x + (qr.bounds.width - size) / 2;
        const top = qr.bounds.y + (qr.bounds.height - size) / 2;
        for (0..qr.width) |y| for (0..qr.width) |x| {
            if (qr.cells[y * qr.width + x] != 0) self.fill(.{
                .x = left + @as(u16, @intCast(x)) * scale,
                .y = top + @as(u16, @intCast(y)) * scale,
                .width = scale,
                .height = scale,
            }, qr.foreground);
        };
    }

    fn drawKeyboard(self: Surface, keyboard: ui.Keyboard, theme: ui.Theme) void {
        for (0..@import("keyboard_layout.zig").count) |index|
            self.drawKeyboardKey(keyboard, theme, index, false, false, 0, 0);
        if (keyboard.state.hasFocus()) self.drawKeyboardKey(
            keyboard,
            theme,
            keyboard.selected,
            true,
            keyboard.state == .pressed or keyboard.state == .activating,
            keyboard.focus_offset_x,
            keyboard.focus_offset_y,
        );
    }

    fn drawKeyboardKey(self: Surface, keyboard: ui.Keyboard, theme: ui.Theme, index: usize, selected: bool, pressed: bool, offset_x: i16, offset_y: i16) void {
        const lower = "1234567890qwertyuiopasdfghjklzxcvbnm";
        const upper = "1234567890QWERTYUIOPASDFGHJKLZXCVBNM";
        const symbols = "1234567890!@#$%^&*()[]{}<>?+-=_/:;,.~`";
        const keys = if (keyboard.symbols) symbols else if (keyboard.uppercase) upper else lower;
        var key_font = font.body;
        key_font.alignment = .center;
        key_font.ink_centered = true;
        const logical = keyboard.keyBounds(index);
        const moved = ui.Rect{
            .x = @intCast(std.math.clamp(@as(i32, logical.x) + offset_x, 0, std.math.maxInt(u16))),
            .y = @intCast(std.math.clamp(@as(i32, logical.y) + offset_y, 0, std.math.maxInt(u16))),
            .width = logical.width,
            .height = logical.height,
        };
        const inset: u16 = if (pressed) 3 else 0;
        const bounds = ui.Rect{ .x = moved.x + inset, .y = moved.y + inset, .width = moved.width - 2 * inset, .height = moved.height - 2 * inset };
        if (self.clips.len != 0) {
            var visible = false;
            for (self.clips) |clip| if (damage.intersects(bounds, clip)) {
                visible = true;
                break;
            };
            if (!visible) return;
        }
        const background = if (selected) theme.selection else theme.surface;
        const foreground = if (selected) theme.selection_text else theme.text;
        self.fillRounded(bounds, background, geometry.radius);
        if (selected and keyboard.state == .boundary) self.stroke(bounds, foreground, 4);
        const value = if (index < 36) keys[index .. index + 1] else switch (index) {
            36 => "Aa",
            37 => "#+",
            38 => "\xe2\x8c\xab",
            else => "Go",
        };
        if (!self.paintText(bounds.x, bounds.y, bounds.width, value, pack(foreground), key_font, "", 1, bounds.height, null, false, 0)) @panic("Text renderer unavailable");
    }

    fn drawChevron(self: Surface, x: u16, y: u16, color: ui.Color) void {
        var glyph_font = font.control;
        glyph_font.size = 38;
        glyph_font.line_height = 42;
        glyph_font.alignment = .center;
        glyph_font.ink_centered = true;
        if (!self.paintText(x -| 4, y -| 9, 28, "›", pack(color), glyph_font, "", 1, 42, null, false, 0)) @panic("Text renderer unavailable");
    }

    fn drawText(self: Surface, x: u16, y: u16, value: []const u8, color: ui.Color, text_font: design.Font) void {
        self.drawTextBounded(x, y, width, value, color, text_font);
    }

    fn drawTextBounded(self: Surface, x: u16, y: u16, max_width: u16, value: []const u8, color: ui.Color, text_font: design.Font) void {
        self.drawTextBoundedLanguage(x, y, max_width, value, color, text_font, "");
    }

    fn drawTextBoundedLanguage(self: Surface, x: u16, y: u16, max_width: u16, value: []const u8, color: ui.Color, text_font: design.Font, language: []const u8) void {
        if (x >= width or y >= height or text_font.size == 0) return;
        const available = @min(max_width, width - x);
        if (!self.paintText(x, y, available, value, pack(color), text_font, language, 1, 96, null, false, 0))
            @panic("PangoFT2 text renderer or required fonts are unavailable");
    }

    fn paintText(self: Surface, x: u16, y: u16, max_width: u16, value: []const u8, color: u32, text_font: design.Font, language: []const u8, lines: u8, max_height: u16, measured: ?*u16, centered: bool, tail: u16) bool {
        return text_pango.drawBlockClipped(self.sink, self.clips, self.pixels, width, x, y, max_width, value, color, text_font, language, lines, max_height, measured, centered, tail);
    }
};

test "long text stays within its bounds and offscreen rectangles are harmless" {
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    @memset(pixels, 0);
    const surface = Surface{ .pixels = pixels };
    surface.fill(.{ .x = 2000, .y = 10, .width = 5, .height = 5 }, artwork_colors.white);
    const long_text: [255]u8 = @splat('B');
    surface.drawTextBounded(10, 10, 90, &long_text, artwork_colors.white, font.body);
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

test "navigation transition makes the destination immediate and direction legible" {
    const themes = @import("theme.zig");
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    var from = ui.Tree{ .theme = themes.light, .background = themes.light.background };
    from.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 0, .width = width, .height = height }, .color = themes.light.background } });
    var to = ui.Tree{ .theme = themes.dark, .background = themes.dark.background };
    to.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 0, .width = width, .height = height }, .color = themes.dark.background } });
    (Surface{ .pixels = pixels }).renderTransition(.{ .base = &from, .overlay = &to, .offset_x = 24 });
    try std.testing.expectEqual(Surface.pack(themes.light.background), pixels[0]);
    try std.testing.expectEqual(Surface.pack(themes.dark.background), pixels[0 * width + 24]);
    try std.testing.expectEqual(Surface.pack(themes.dark.background), pixels[500 * width + 500]);
    try std.testing.expectEqual(Surface.pack(themes.dark.background), pixels[height * width - 1]);

    (Surface{ .pixels = pixels }).renderTransition(.{ .base = &from, .overlay = &to, .offset_x = -24 });
    try std.testing.expectEqual(Surface.pack(themes.dark.background), pixels[0]);
    try std.testing.expectEqual(Surface.pack(themes.dark.background), pixels[width - 25]);
    try std.testing.expectEqual(Surface.pack(themes.light.background), pixels[width - 1]);
}

test "meter endpoints remain inside their declared component bounds" {
    const themes = @import("theme.zig");
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    var tree = ui.Tree{ .theme = themes.light, .background = themes.light.background };
    tree.add(.{ .meter = .{ .id = @import("interaction.zig").Id.scoped(.brightness_meter, 0), .bounds = .{ .x = 100, .y = 100, .width = 300, .height = 40 }, .value = 1000, .track = themes.light.surface, .fill = themes.light.text, .thumb = themes.light.accent } });
    (Surface{ .pixels = pixels }).render(&tree);
    const background = Surface.pack(themes.light.background);
    try std.testing.expectEqual(background, pixels[99 * width + 99]);
    try std.testing.expectEqual(background, pixels[141 * width + 401]);
    try std.testing.expect(pixels[120 * width + 385] != background);
}

test "activity dots remain inside their declared component bounds" {
    const themes = @import("theme.zig");
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    var tree = ui.Tree{ .theme = themes.light, .background = themes.light.background };
    tree.add(.{ .activity = .{ .bounds = .{ .x = 100, .y = 100, .width = 48, .height = 26 }, .color = themes.light.accent, .phase = 500 } });
    (Surface{ .pixels = pixels }).render(&tree);
    const background = Surface.pack(themes.light.background);
    var painted: usize = 0;
    for (pixels, 0..) |pixel, index| if (pixel != background) {
        painted += 1;
        try std.testing.expect(index % width >= 100 and index % width < 148);
        try std.testing.expect(index / width >= 100 and index / width < 126);
    };
    try std.testing.expect(painted > 0);
}

test "keyboard press visibly depresses the focused key" {
    const themes = @import("theme.zig");
    const focused_pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(focused_pixels);
    const pressed_pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pressed_pixels);
    var tree = ui.Tree{ .theme = themes.light, .background = themes.light.background };
    tree.add(.{ .keyboard = .{ .bounds = .{ .x = 48, .y = 260, .width = 928, .height = 328 }, .selected = 13 } });
    (Surface{ .pixels = focused_pixels }).render(&tree);
    try std.testing.expect(tree.setInteraction(tree.focusedId().?, .pressed));
    (Surface{ .pixels = pressed_pixels }).render(&tree);
    try std.testing.expect(!std.mem.eql(u32, focused_pixels, pressed_pixels));
    const key = tree.elements[0].keyboard.selectedBounds();
    const sample = (key.y + key.height / 2) * width + key.x + 1;
    try std.testing.expectEqual(Surface.pack(themes.light.selection), focused_pixels[sample]);
    try std.testing.expectEqual(Surface.pack(themes.light.surface), pressed_pixels[sample]);
}

test "quiet editorial focus is visible without a resting outline" {
    const themes = @import("theme.zig");
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    var tree = ui.Tree{ .theme = themes.light, .background = themes.light.background };
    tree.add(.{ .focus_frame = .{
        .state = .focused,
        .bounds = .{ .x = 80, .y = 120, .width = 360, .height = 72 },
        .presentation = .quiet,
    } });
    (Surface{ .pixels = pixels }).render(&tree);
    const background = Surface.pack(themes.light.background);
    const center = (120 + 36) * width + 80 + 180;
    try std.testing.expect(pixels[center] != background);
    try std.testing.expectEqual(background, pixels[119 * width + 80]);
}

test "lowercase and uppercase preserve distinct letterforms" {
    const a = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(a);
    const b = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(b);
    @memset(a, 0);
    @memset(b, 0);
    (Surface{ .pixels = a }).drawText(10, 10, "hello pong", artwork_colors.white, font.body);
    (Surface{ .pixels = b }).drawText(10, 10, "HELLO PONG", artwork_colors.white, font.body);
    try std.testing.expect(!std.mem.eql(u32, a, b));
    try std.testing.expect(std.mem.count(u32, a, &.{0}) < a.len);
    try std.testing.expect(std.mem.count(u32, b, &.{0}) < b.len);
}

test "multiline titles use their height and remain inside the text rectangle" {
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    @memset(pixels, Surface.pack(artwork_colors.paper));
    var tree = ui.Tree{ .background = artwork_colors.paper };
    tree.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 40, .width = 400, .height = 120 }, .value = "A long game title that must occupy two lines", .color = artwork_colors.ink, .font = font.body, .lines = 2 } });
    (Surface{ .pixels = pixels }).render(&tree);
    var second_line = false;
    for (pixels, 0..) |pixel, index| {
        if (pixel == Surface.pack(artwork_colors.paper)) continue;
        const x = index % width;
        const y = index / width;
        try std.testing.expect(x >= 40 and x < 440 and y >= 40 and y < 160);
        if (y >= 90) second_line = true;
    }
    try std.testing.expect(second_line);
}

test "overlay disclosures paint a bounded trailing affordance" {
    const pixels_without = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels_without);
    const pixels_with = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels_with);
    const theme = @import("theme.zig").light;
    var without = ui.Tree{ .theme = theme, .background = theme.background };
    without.add(.{ .overlay_row = .{ .bounds = .{ .x = 28, .y = 138, .width = 968, .height = 96 }, .label = "Settings", .detail = "", .selected = false, .disclosure = false } });
    var with = ui.Tree{ .theme = theme, .background = theme.background };
    with.add(.{ .overlay_row = .{ .bounds = .{ .x = 28, .y = 138, .width = 968, .height = 96 }, .label = "Settings", .detail = "", .selected = false, .disclosure = true } });
    (Surface{ .pixels = pixels_without }).render(&without);
    (Surface{ .pixels = pixels_with }).render(&with);
    var changed: usize = 0;
    var leftmost: usize = width;
    for (pixels_without, pixels_with, 0..) |a, b, index| if (a != b) {
        changed += 1;
        leftmost = @min(leftmost, index % width);
    };
    try std.testing.expect(changed > 0);
    try std.testing.expect(leftmost >= 940);
}

test "theme changes interface surfaces but preserves artwork pixels" {
    const views = @import("ui.zig");
    const a = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(a);
    const b = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(b);
    const themes = @import("theme.zig");
    var light = views.foyer(themes.light, 0);
    var dark = views.foyer(themes.dark, 0);
    (Surface{ .pixels = a }).render(&light);
    (Surface{ .pixels = b }).render(&dark);
    try std.testing.expect(a[0] != b[0]);
    try std.testing.expect(a[150 * width + 50] != b[150 * width + 50]);
    light = .{ .theme = themes.light, .background = themes.light.background };
    dark = .{ .theme = themes.dark, .background = themes.dark.background };
    const cover = ui.Element{ .cover = .{ .bounds = .{ .x = 100, .y = 100, .width = 200, .height = 300 }, .kind = .falling } };
    light.add(cover);
    dark.add(cover);
    (Surface{ .pixels = a }).render(&light);
    (Surface{ .pixels = b }).render(&dark);
    for (100..400) |y| try std.testing.expectEqualSlices(u32, a[y * width + 100 .. y * width + 300], b[y * width + 100 .. y * width + 300]);
}

test "resolved styles render identically to literal colours and ignore later theme changes" {
    const a = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(a);
    const b = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(b);
    const themes = @import("theme.zig");
    var configured = ui.Tree{ .theme = themes.dark, .background = themes.dark.background };
    configured.add(.{ .menu_row = .{ .bounds = .{ .x = 40, .y = 140, .width = 944, .height = 92 }, .label = "Selected game", .selected = true } });
    var literal = ui.Tree{ .background = themes.dark.background };
    literal.elements[0] = .{ .menu_row = .{
        .bounds = .{ .x = 40, .y = 140, .width = 944, .height = 92 },
        .label = "Selected game",
        .selected = true,
        .state = .focused,
        .style = .{
            .base = themes.dark.background,
            .background = themes.dark.background,
            .text = themes.dark.text,
            .detail = themes.dark.muted,
            .border = themes.dark.background,
            .accent = themes.dark.accent,
            .shadow = themes.dark.background,
        },
    } };
    literal.len = 1;
    configured.theme = themes.light;
    (Surface{ .pixels = a }).render(&configured);
    (Surface{ .pixels = b }).render(&literal);
    try std.testing.expectEqualSlices(u32, a, b);
}

test "font weight alignment and line height are independent of size" {
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    var tree = ui.Tree{ .background = @import("theme.zig").light.background };
    tree.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 40, .width = 400, .height = 120 }, .value = "Two lines\nof text", .color = @import("theme.zig").light.text, .font = .{ .size = 28, .weight = .semibold, .alignment = .end, .line_height = 48 }, .lines = 2 } });
    (Surface{ .pixels = pixels }).render(&tree);
    var ink: usize = 0;
    for (pixels, 0..) |pixel, index| if (pixel != Surface.pack(tree.background)) {
        try std.testing.expect(index % width >= 40 and index % width < 440);
        try std.testing.expect(index / width >= 40 and index / width < 136);
        try std.testing.expect(index % width > 200);
        ink += 1;
    };

    try std.testing.expect(ink > 100);
}

test "wrapped game titles and details stay inside their row" {
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 138, .width = 968, .height = 134 }, .label = "The Legend of Zelda: A Very Long Adventure Across Several Kingdoms", .detail = "Super Nintendo", .lines = 2, .selected = true, .disclosure = false } });
    (Surface{ .pixels = pixels }).render(&tree);
    for (pixels, 0..) |pixel, index| {
        if (pixel == Surface.pack(theme.background)) continue;
        // The focus plate owns a three-pixel depth edge below its content box.
        try std.testing.expect(index / width >= 138 and index / width < 275);
        try std.testing.expect(index % width >= 28 and index % width < 996);
    }
}

test "menu labels are visibly centred in their focus plate" {
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    const theme = @import("theme.zig").light;
    for ([_][]const u8{ "Games", "Settings", "Play again", "Écran", "日本語" }) |label| {
        var tree = ui.Tree{ .theme = theme, .background = theme.background };
        tree.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 200, .width = 968, .height = 74 }, .label = label, .selected = true, .disclosure = false } });
        (Surface{ .pixels = pixels }).render(&tree);
        var top: usize = height;
        var bottom: usize = 0;
        for (200..274) |y| {
            for (48..948) |x| {
                if (pixels[y * width + x] == Surface.pack(theme.text)) continue;
                top = @min(top, y);
                bottom = @max(bottom, y);
            }
        }
        try std.testing.expect(top < bottom);
        const above = top - 200;
        const below = 273 - bottom;
        try std.testing.expect(@max(above, below) - @min(above, below) <= 2);
    }
}
