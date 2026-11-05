// SPDX-License-Identifier: GPL-2.0-only
const design = @import("design.zig");
const font = design.typeface;
const geometry = design.geometry;
const catalog = @import("catalog.zig");
const settings_model = @import("settings.zig");

pub const Color = @import("color.zig").Color;
pub const Theme = @import("theme.zig").Theme;

pub const Rect = struct { x: u16, y: u16, width: u16, height: u16 };
pub const Text = struct { bounds: Rect, value: []const u8, color: Color, font: design.Font = font.body, language: []const u8 = "", lines: u8 = 1 };
pub const TextBlock = struct {
    bounds: Rect,
    title: []const u8,
    detail: []const u8,
    color: Color,
    detail_color: Color,
    title_font: design.Font = font.body,
    detail_font: design.Font = font.caption,
    lines: u8 = 2,
    detail_lines: u8 = 1,
    gap: u16 = 16,
    centered: bool = false,
    detail_above: bool = false,
};
pub const Bar = struct { bounds: Rect, color: Color, radius: u16 = 0 };
pub const Scrim = struct { bounds: Rect, color: Color, alpha: u8 };
pub const RowStyle = struct {
    background: Color,
    text: Color,
    detail: Color,
    border: Color,
    accent: Color,
};
pub const ArtworkStyle = struct { shadow: Color, edge: Color, surface: Color, text: Color };
pub const MenuRow = struct {
    label_font: design.Font = font.body,
    lines: u8 = 1,
    style: RowStyle = @import("std").mem.zeroes(RowStyle),
    bounds: Rect,
    label: []const u8,
    detail: []const u8 = "",
    selected: bool,
    disclosure: bool = true,
};
pub const Battery = struct { bounds: Rect, percent: u8, outline: Color = @import("std").mem.zeroes(Color), charge: Color = @import("std").mem.zeroes(Color) };
pub const Cover = struct { bounds: Rect, kind: catalog.Cover };
pub const LibraryView = enum { list, shelf, grid };
pub const Cartridge = struct {
    style: ArtworkStyle = @import("std").mem.zeroes(ArtworkStyle),
    bounds: Rect,
    platform: []const u8,
    texture: ?@import("asset_manifest.zig").Texture,
    sprite: ?@import("asset_manifest.zig").Texture,
    selected: bool = false,
    dim: u8 = 0,
    tilt: i16 = 0,
    clip_left: u16 = 0,
    plain_fallback: bool = false,
};
pub const OverlayRow = struct {
    style: RowStyle = @import("std").mem.zeroes(RowStyle),
    bounds: Rect,
    label: []const u8,
    detail: []const u8,
    value: []const u8 = "",
    selected: bool,
    disclosure: bool = true,
};
pub const Element = union(enum) {
    bar: Bar,
    scrim: Scrim,
    text: Text,
    text_block: TextBlock,
    menu_row: MenuRow,
    battery: Battery,
    cover: Cover,
    cartridge: Cartridge,
    overlay_row: OverlayRow,
};

pub const Tree = struct {
    theme: Theme = @import("theme.zig").light,
    background: Color,
    preserve_background: bool = false,
    // SAFETY: callers only read the initialized prefix below `len`.
    elements: [48]Element = undefined,
    len: usize = 0,

    pub fn add(self: *Tree, element: Element) void {
        var resolved = element;
        switch (resolved) {
            .menu_row => |*row| row.style = self.rowStyle(row.selected),
            .overlay_row => |*row| row.style = self.rowStyle(row.selected),
            .cartridge => |*item| item.style = .{ .shadow = self.theme.shadow, .edge = if (item.selected) self.theme.accent else self.theme.border, .surface = self.theme.surface, .text = self.theme.muted },
            .battery => |*item| {
                item.outline = self.theme.text;
                item.charge = self.theme.accent;
            },
            else => {},
        }
        self.elements[self.len] = resolved;
        self.len += 1;
    }

    fn rowStyle(self: *const Tree, selected: bool) RowStyle {
        return .{ .background = if (selected) self.theme.selection else self.theme.background, .text = if (selected) self.theme.selection_text else self.theme.text, .detail = if (selected) self.theme.selection_text else self.theme.muted, .border = self.theme.border, .accent = self.theme.accent };
    }

    pub fn slice(self: *const Tree) []const Element {
        return self.elements[0..self.len];
    }
};

const menu = struct {
    fn overlayRow(index: usize) Rect {
        return .{ .x = 28, .y = geometry.overlay_row_top + @as(u16, @intCast(index)) * geometry.overlay_row_step, .width = 968, .height = geometry.overlay_row_height };
    }
};

fn overlayFrame(result: *Tree, title: []const u8, game_title: []const u8) void {
    header(result, title);
    textLabel(result, .{ .x = 48, .y = 106, .width = 928, .height = 42 }, game_title, result.theme.muted, font.caption);
}

pub fn overlayPause(theme: Theme, game_title: []const u8, selected: usize, state_slot: usize, performance: []const u8, notice: []const u8) Tree {
    const labels = [_][]const u8{ "Continue", "Save state", "Load state", "Performance", "Save and exit" };
    const slots = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3" };
    var result = Tree{ .theme = theme, .background = theme.background };
    overlayFrame(&result, "Game menu", game_title);
    for (labels, 0..) |label, index| {
        result.add(.{ .overlay_row = .{
            .bounds = menu.overlayRow(index),
            .label = label,
            .detail = "",
            .value = if (index == 1) slots[state_slot] else if (index == 3) performance else "",
            .selected = index == selected,
            .disclosure = index == 2,
        } });
    }
    footer(&result, &.{ .{ .control = .back, .label = "Continue" }, .{ .control = .confirm, .label = "Select" } });
    if (notice.len != 0) showNotice(&result, notice);
    return result;
}

pub fn overlayStates(theme: Theme, game_title: []const u8, selected: usize, notice: []const u8, available: [4]bool) Tree {
    const labels = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3", "Automatic save" };
    const details = [_][]const u8{ "Manual save", "Manual save", "Manual save", "Latest session" };
    var result = Tree{ .theme = theme, .background = theme.background };
    var any = false;
    for (available) |present| any = any or present;
    if (!any) {
        result = message(theme, "Load state", "No saved states", "Save a state from the game menu to return to this point later.");
        footer(&result, &.{.{ .control = .back, .label = "Game menu" }});
        if (notice.len != 0) showNotice(&result, notice);
        return result;
    }
    overlayFrame(&result, "Load state", game_title);
    for (labels, details, 0..) |label, detail, index| {
        result.add(.{ .overlay_row = .{
            .bounds = .{ .x = 28, .y = 169 + @as(u16, @intCast(index)) * 123, .width = 968, .height = 123 },
            .label = label,
            .detail = if (available[index]) detail else "Empty",
            .selected = index == selected,
            .disclosure = false,
        } });
    }
    footer(&result, &.{ .{ .control = .back, .label = "Game menu" }, .{ .control = .confirm, .label = if (available[selected]) "Load" else "Empty" } });
    if (notice.len != 0) showNotice(&result, notice);
    return result;
}

const layout = struct {
    const margin = design.spacing.margin;
    const footer_y = geometry.footer_y;
};

fn textLabel(result: *Tree, bounds: Rect, value: []const u8, color: Color, text_font: design.Font) void {
    result.add(.{ .text = .{ .bounds = bounds, .value = value, .color = color, .font = text_font } });
}

fn header(result: *Tree, title: []const u8) void {
    const theme = result.theme;
    textLabel(result, .{ .x = layout.margin, .y = geometry.header_y, .width = 800, .height = 58 }, title, theme.text, font.title);
}

pub const Hint = struct { control: @import("input.zig").HintControl, label: []const u8 };

fn hint(result: *Tree, x: u16, y: u16, label_width: u16, item: Hint) void {
    const size: u16 = switch (item.control) {
        .view, .filter, .menu => geometry.glyph_size,
        else => 40,
    };
    const colour = result.theme.muted;
    switch (item.control) {
        .confirm, .back, .horizontal => {
            const symbol = switch (item.control) {
                .confirm => "A",
                .back => "B",
                else => "↔",
            };
            if (item.control != .horizontal) {
                result.add(.{ .bar = .{ .bounds = .{ .x = x, .y = y + 1, .width = 38, .height = 38 }, .color = colour, .radius = 19 } });
                result.add(.{ .bar = .{ .bounds = .{ .x = x + 2, .y = y + 3, .width = 34, .height = 34 }, .color = result.background, .radius = 17 } });
            }
            var glyph_font = font.control;
            glyph_font.alignment = .center;
            result.add(.{ .text = .{ .bounds = .{ .x = x, .y = y, .width = size, .height = size }, .value = symbol, .color = colour, .font = glyph_font } });
        },
        .view, .filter, .menu => {
            // The upper controls are narrow pills; the lower row has round keys.
            const upper = item.control != .menu;
            const count: u16 = if (upper) 2 else 3;
            const key_width: u16 = if (upper) 28 else 18;
            const key_height: u16 = if (upper) 12 else 18;
            const gap: u16 = if (upper) 8 else 5;
            for (0..count) |index| {
                const bounds = Rect{ .x = x + @as(u16, @intCast(index)) * (key_width + gap), .y = y + (40 - key_height) / 2, .width = key_width, .height = key_height };
                result.add(.{ .bar = .{ .bounds = bounds, .color = colour, .radius = key_height / 2 } });
                if (index != (if (item.control == .filter) @as(usize, 1) else 0)) result.add(.{ .bar = .{
                    .bounds = .{ .x = bounds.x + 2, .y = bounds.y + 2, .width = key_width - 4, .height = key_height - 4 },
                    .color = result.background,
                    .radius = key_height / 2 - 2,
                } });
            }
        },
    }
    textLabel(result, .{ .x = x + size + geometry.hint_gap / 2, .y = y, .width = label_width, .height = 44 }, item.label, colour, font.control);
}

fn hints(result: *Tree, bounds: Rect, items: []const Hint) void {
    if (items.len == 0) return;
    // Space between complete hints, rather than anchoring each to an equal cell.
    var widths: [4]u16 = @splat(0);
    var total: u16 = 0;
    for (items, 0..) |item, index| {
        const icon: u16 = switch (item.control) {
            .view, .filter, .menu => geometry.glyph_size,
            else => 40,
        };
        widths[index] = icon + 8 + @as(u16, @intCast(item.label.len)) * 17;
        total += widths[index];
    }
    const gap = if (items.len > 1) (bounds.width -| total) / @as(u16, @intCast(items.len - 1)) else 0;
    var x = bounds.x;
    for (items, 0..) |item, index| {
        hint(result, x, bounds.y, widths[index], item);
        x += widths[index] + gap;
    }
}

fn footer(result: *Tree, items: []const Hint) void {
    hints(result, .{ .x = layout.margin, .y = layout.footer_y, .width = geometry.width - 2 * layout.margin, .height = 44 }, items);
}

fn artwork(result: *Tree, game: catalog.Game, bounds: Rect, cart: bool, dim: u8, tilt: i16) void {
    const sprite = if (cart) game.assets.card orelse game.assets.sprite else game.assets.cover;
    if (sprite == null and game.assets.preview == null) {
        result.add(.{ .bar = .{ .bounds = bounds, .color = result.theme.surface, .radius = geometry.radius } });
        result.add(.{ .text = .{ .bounds = .{ .x = bounds.x + 16, .y = bounds.y + bounds.height / 4, .width = bounds.width -| 32, .height = @min(120, bounds.height / 2) }, .value = game.system, .color = result.theme.muted, .font = font.caption, .lines = 2 } });
        return;
    }
    result.add(.{ .cartridge = .{
        .bounds = bounds,
        .platform = game.platform_id,
        .texture = game.assets.preview,
        .sprite = sprite,
        .selected = false,
        .dim = dim,
        .tilt = tilt,
        .plain_fallback = !cart,
    } });
}

fn caption(result: *Tree, game: catalog.Game) void {
    var title_font = font.body;
    title_font.weight = .medium;
    title_font.alignment = .center;
    title_font.line_height = 51;
    var system_font = font.caption;
    system_font.alignment = .center;
    result.add(.{ .text_block = .{ .bounds = .{ .x = 48, .y = 530, .width = 928, .height = 148 }, .title = game.title, .detail = game.system, .color = result.theme.text, .detail_color = result.theme.muted, .title_font = title_font, .detail_font = system_font } });
}

pub fn home(theme: Theme, selected: usize) Tree {
    return homeSession(theme, selected, null, false);
}

pub fn homeSession(theme: Theme, selected: usize, recent: ?catalog.Game, resumable: bool) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Brick");
    if (recent) |game| {
        var title_font = font.body;
        title_font.size = 50;
        title_font.line_height = 57;
        title_font.weight = .medium;
        result.add(.{ .text_block = .{ .bounds = .{ .x = 48, .y = 161, .width = 566, .height = 269 }, .title = game.title, .detail = if (resumable) "Ready to resume" else "Last played", .color = theme.text, .detail_color = theme.muted, .title_font = title_font, .lines = 3, .gap = 20, .centered = true, .detail_above = true } });
        artwork(&result, game, .{ .x = 665, .y = 161, .width = 311, .height = 269 }, false, 0, 0);
    }
    const items: []const []const u8 = if (recent != null) &.{ if (resumable) "Resume" else "Play again", "Games", "Settings" } else &.{ "Games", "Settings" };
    for (items, 0..) |item, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = 28, .y = (if (recent != null) @as(u16, 453) else 238) + @as(u16, @intCast(index)) * (if (recent != null) @as(u16, 74) else 150), .width = 968, .height = if (recent != null) 74 else 150 },
        .label = item,
        .label_font = if (recent == null) .{ .size = 56, .line_height = 67 } else font.body,
        .selected = selected == index,
        .disclosure = false,
    } });
    footer(&result, &.{.{ .control = .confirm, .label = if (recent == null) "Open" else if (selected == 0) (if (resumable) "Resume" else "Play") else "Open" }});
    return result;
}

pub fn library(theme: Theme, games: []const catalog.Game, selected: usize, view: LibraryView, shelf_offset: i16) Tree {
    return libraryCollection(theme, .{ .games = games }, selected, view, shelf_offset);
}

pub fn libraryCollection(theme: Theme, collection: catalog.Collection, selected: usize, view: LibraryView, shelf_offset: i16) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Games");
    var right_font = font.caption;
    right_font.alignment = .end;
    textLabel(&result, .{ .x = 480, .y = 41, .width = 420, .height = 44 }, collection.label(), theme.muted, right_font);
    hint(&result, 912, 41, 0, .{ .control = .filter, .label = "" });
    const count = collection.len();
    if (count == 0) {
        textLabel(&result, .{ .x = 48, .y = 224, .width = 928, .height = 64 }, "No games yet", theme.text, font.title);
        result.add(.{ .text = .{ .bounds = .{ .x = 48, .y = 312, .width = 864, .height = 100 }, .value = "Add games to the Roms folder on your SD card.", .color = theme.muted, .font = font.body, .lines = 2 } });
        footer(&result, &.{.{ .control = .back, .label = "Home" }});
        return result;
    }
    const game = collection.at(selected);
    switch (view) {
        .list => {
            const visible = @min(count, 4);
            const first = if (selected > 1) @min(selected - 1, count - visible) else 0;
            for (first..first + visible) |index| {
                const entry = collection.at(index);
                result.add(.{ .menu_row = .{
                    .bounds = .{ .x = 28, .y = 138 + @as(u16, @intCast(index - first)) * 134, .width = 968, .height = 134 },
                    .label = entry.title,
                    .detail = if (collection.system == null) entry.system else "",
                    .selected = index == selected,
                    .disclosure = false,
                    .lines = if (index == selected) 2 else 1,
                } });
            }
        },
        .grid => {
            const first = (selected / 6) * 6;
            for (first..@min(first + 6, count)) |index| {
                const x: u16 = 48 + @as(u16, @intCast((index - first) % 3)) * 316;
                const y: u16 = 136 + @as(u16, @intCast((index - first) / 3)) * 184;
                const active = index == selected;
                result.add(.{ .bar = .{ .bounds = .{ .x = x, .y = y, .width = 292, .height = 172 }, .color = if (active) theme.text else theme.background } });
                result.add(.{ .bar = .{ .bounds = .{ .x = x + 3, .y = y + 3, .width = 286, .height = 166 }, .color = theme.background } });
                artwork(&result, collection.at(index), .{ .x = x + 12, .y = y + 10, .width = 268, .height = 152 }, false, 0, 0);
            }
            caption(&result, game);
        },
        .shelf => {
            const order = [_]i8{ -4, 4, -3, 3, -2, 2, -1, 1, 0 };
            for (order) |relative| {
                const index = @as(i64, @intCast(selected)) + relative;
                if (index < 0 or index >= count) continue;
                const pose = shelfPose(relative, shelf_offset);
                artwork(&result, collection.at(@intCast(index)), pose.bounds, true, pose.dim, pose.tilt);
                if (result.elements[result.len - 1] == .cartridge) result.elements[result.len - 1].cartridge.clip_left = pose.clip_left;
            }
            caption(&result, game);
        },
    }
    footer(&result, &.{ .{ .control = .back, .label = "Home" }, .{ .control = .view, .label = "View" }, .{ .control = .confirm, .label = "Play" } });
    return result;
}

const ShelfPose = struct { bounds: Rect, dim: u8, tilt: i16, clip_left: u16 };

fn shelfPose(relative: i8, offset: i16) ShelfPose {
    const position = @as(i32, relative) * 1000 + offset;
    const distance = @abs(position);
    // The fourth neighbour enters from outside the viewport during navigation.
    const center = 512 + @divTrunc(position * 184, 1000);
    const width: i32 = if (distance < 1000) 389 - @as(i32, @intCast(distance * 133 / 1000)) else 256;
    return .{
        .bounds = .{ .x = @intCast(@max(0, center - @divTrunc(width, 2))), .y = 154, .width = @intCast(width), .height = 330 },
        .clip_left = @intCast(@max(0, @divTrunc(width, 2) - center)),
        .dim = @intCast(@min(71, distance * 71 / 1000)),
        .tilt = 0,
    };
}

pub fn gameDetail(theme: Theme, game: catalog.Game, launch_failed: ?[]const u8) Tree {
    var result = message(theme, if (launch_failed != null) "Unable to start" else "Starting game", game.title, launch_failed orelse "Opening emulator…");
    if (launch_failed != null) footer(&result, &.{ .{ .control = .back, .label = "Games" }, .{ .control = .confirm, .label = "Retry" } });
    return result;
}

pub fn message(theme: Theme, title: []const u8, subject: []const u8, detail: []const u8) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, title);
    var title_font = font.body;
    title_font.size = 50;
    title_font.weight = .medium;
    title_font.line_height = 60;
    var detail_font = font.caption;
    detail_font.size = 35;
    detail_font.line_height = 51;
    result.add(.{ .text_block = .{ .bounds = .{ .x = 48, .y = 223, .width = 900, .height = 268 }, .title = subject, .detail = detail, .color = theme.text, .detail_color = theme.muted, .title_font = title_font, .detail_font = detail_font, .detail_lines = 2, .gap = 31 } });
    return result;
}

pub fn confirmation(theme: Theme, title: []const u8, subject: []const u8, detail: []const u8, action: []const u8, selected: usize) Tree {
    var result = message(theme, title, subject, detail);
    for ([_][]const u8{ "Cancel", action }, 0..) |label, index| result.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 492 + @as(u16, @intCast(index)) * 88, .width = 968, .height = 88 }, .label = label, .selected = selected == index, .disclosure = false } });
    footer(&result, &.{ .{ .control = .back, .label = "Cancel" }, .{ .control = .confirm, .label = "Select" } });
    return result;
}

pub fn choice(theme: Theme, title: []const u8, labels: []const []const u8, selected: usize, active: ?usize, note: []const u8, back: []const u8) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, title);
    const visible = @min(labels.len, if (note.len != 0) @as(usize, 4) else 6);
    const first = @min(selected -| 2, labels.len - visible);
    const bottom: u16 = if (note.len != 0 or @import("std").mem.eql(u8, title, "Appearance")) 530 else 676;
    const step = (bottom - 138) / @as(u16, @intCast(@max(1, visible)));
    for (first..first + visible) |index| result.add(.{ .overlay_row = .{
        .bounds = .{ .x = 28, .y = 138 + @as(u16, @intCast(index - first)) * step, .width = 968, .height = step },
        .label = labels[index],
        .value = if (active == index) "✓" else "",
        .detail = "",
        .selected = selected == index,
        .disclosure = false,
    } });
    if (note.len != 0) result.add(.{ .text = .{ .bounds = .{ .x = 48, .y = 550, .width = 928, .height = 104 }, .value = note, .color = theme.muted, .font = font.caption, .lines = 2 } });
    footer(&result, &.{ .{ .control = .back, .label = back }, .{ .control = .confirm, .label = "Select" } });
    return result;
}

pub fn setting(item: settings_model.Setting, selected: usize, active: usize, values: settings_model.Values) Tree {
    const theme = values.appearance.colors();
    if (item == .brightness) {
        var result = Tree{ .theme = theme, .background = theme.background };
        header(&result, "Brightness");
        var large = font.brand;
        large.alignment = .center;
        large.size = 112;
        large.line_height = 135;
        large.weight = .regular;
        textLabel(&result, .{ .x = 82, .y = 223, .width = 860, .height = 135 }, values.value(.brightness), theme.text, large);
        result.add(.{ .bar = .{ .bounds = .{ .x = 96, .y = 410, .width = 832, .height = 8 }, .color = theme.surface } });
        result.add(.{ .bar = .{ .bounds = .{ .x = 96, .y = 410, .width = @intCast(@as(u32, values.brightness) * 832 / 10), .height = 8 }, .color = theme.text } });
        var note_font = font.caption;
        note_font.alignment = .center;
        textLabel(&result, .{ .x = 82, .y = 502, .width = 860, .height = 40 }, "Left / right to adjust", theme.muted, note_font);
        footer(&result, &.{.{ .control = .back, .label = "Settings" }});
        return result;
    }
    const note: []const u8 = switch (item) {
        .display_timeout => "Turn off the display after inactivity. The device remains awake.",
        .suspend_timeout => "Enter low-power sleep after inactivity when available. Bluetooth disconnects.",
        .performance => "Balances responsiveness and power use. Demanding games may need Performance.",
        else => "",
    };
    return choice(theme, settings_model.title(item), settings_model.labels(item), selected, active, note, "Settings");
}

pub fn settings(selected: usize, values: settings_model.Values) Tree {
    const theme = values.appearance.colors();
    const items = [_][]const u8{ "Brightness", "Performance", "Screen off", "Suspend", "Appearance" };
    const details = [_][]const u8{ values.value(.brightness), values.value(.performance), values.value(.display_timeout), values.value(.suspend_timeout), values.value(.appearance) };
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Settings");
    for (items, details, 0..) |item, value, index| result.add(.{ .overlay_row = .{
        .bounds = .{ .x = 28, .y = geometry.settings_top + @as(u16, @intCast(index)) * geometry.settings_step, .width = 968, .height = geometry.settings_height },
        .label = item,
        .detail = "",
        .value = value,
        .selected = index == selected,
        .disclosure = false,
    } });
    footer(&result, &.{ .{ .control = .back, .label = "Home" }, .{ .control = .confirm, .label = "Open" } });
    return result;
}

pub fn splash(theme: Theme) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    var brand = font.brand;
    brand.alignment = .center;
    textLabel(&result, .{ .x = 48, .y = 338, .width = 928, .height = 92 }, "Brick", theme.text, brand);
    return result;
}

pub fn languageProof(theme: Theme) Tree {
    const left = [_][]const u8{
        "Français — Pokémon Écarlate",
        "Español — Continuar partida",
        "Português — Coração de Fogo",
        "Polski — Łowca przygód",
        "Ελληνικά — Συνέχεια παιχνιδιού",
        "Русский — Продолжить игру",
        "Українська — Продовжити гру",
    };
    const right = [_][]const u8{
        "العربية — متابعة اللعب",
        "עברית — המשך משחק",
        "हिन्दी — खेल जारी रखें",
        "ไทย — เล่นต่อ",
        "日本語 — ゲームを続ける",
        "简体中文 — 继续游戏",
        "繁體中文 — 繼續遊戲",
        "한국어 — 게임 계속하기",
    };
    const left_languages = [_][]const u8{ "fr", "es", "pt", "pl", "el", "ru", "uk" };
    const right_languages = [_][]const u8{ "ar", "he", "hi", "th", "ja", "zh-Hans", "zh-Hant", "ko" };
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Language proof");
    result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 96, .width = 420, .height = 34 }, .value = "Shaping and fallback", .color = theme.accent, .font = font.caption } });
    for (left, left_languages, 0..) |sample, language, index|
        result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 150 + @as(u16, @intCast(index)) * 76, .width = 438, .height = 48 }, .value = sample, .color = theme.text, .font = font.caption, .language = language } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 510, .y = 118, .width = 2, .height = 590 }, .color = theme.border } });
    for (right, right_languages, 0..) |sample, language, index|
        result.add(.{ .text = .{ .bounds = .{ .x = 544, .y = 126 + @as(u16, @intCast(index)) * 70, .width = 438, .height = 48 }, .value = sample, .color = theme.text, .font = font.caption, .language = language } });
    return result;
}

pub fn showNotice(tree: *Tree, notice: []const u8) void {
    tree.add(.{ .bar = .{ .bounds = .{ .x = layout.margin, .y = layout.footer_y, .width = geometry.width - 2 * layout.margin, .height = 44 }, .color = tree.theme.background } });
    textLabel(tree, .{ .x = layout.margin, .y = layout.footer_y, .width = geometry.width - 2 * layout.margin, .height = 44 }, notice, tree.theme.text, font.control);
}

test "light and dark appearances preserve component geometry and typography" {
    const std = @import("std");
    const themes = @import("theme.zig");
    const light_screens = [_]Tree{ home(themes.light, 0), library(themes.light, &catalog.games, 0, .list, 0), library(themes.light, &catalog.games, 0, .shelf, 0), library(themes.light, &catalog.games, 0, .grid, 0), settings(0, .{}), overlayStates(themes.light, "Game", 0, "", @splat(false)), splash(themes.light) };
    const dark_screens = [_]Tree{ home(themes.dark, 0), library(themes.dark, &catalog.games, 0, .list, 0), library(themes.dark, &catalog.games, 0, .shelf, 0), library(themes.dark, &catalog.games, 0, .grid, 0), settings(0, .{ .appearance = .dark }), overlayStates(themes.dark, "Game", 0, "", @splat(false)), splash(themes.dark) };
    for (&light_screens, &dark_screens) |*light_screen, *dark_screen| {
        try std.testing.expectEqual(light_screen.len, dark_screen.len);
        for (light_screen.slice(), dark_screen.slice()) |a, b| {
            try std.testing.expectEqual(std.meta.activeTag(a), std.meta.activeTag(b));
            switch (a) {
                inline else => |item, tag| try std.testing.expectEqualDeep(item.bounds, @field(b, @tagName(tag)).bounds),
            }
            if (a == .text) try std.testing.expectEqualDeep(a.text.font, b.text.font);
        }
    }
}

pub fn saveSlots(theme: Theme, title: []const u8, selected: usize, available: [4]bool) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    overlayFrame(&result, "Save state", title);
    for ([_][]const u8{ "Slot 1", "Slot 2", "Slot 3" }, 0..) |label, index| result.add(.{ .overlay_row = .{
        .bounds = .{ .x = 28, .y = 169 + @as(u16, @intCast(index)) * 164, .width = 968, .height = 164 },
        .label = label,
        .detail = if (available[index]) "Saved state" else "Empty",
        .selected = selected == index,
        .disclosure = false,
    } });
    footer(&result, &.{ .{ .control = .back, .label = "Game menu" }, .{ .control = .confirm, .label = "Save" } });
    return result;
}
