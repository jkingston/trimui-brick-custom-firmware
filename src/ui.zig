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
        return .{ .x = 192, .y = geometry.overlay_row_top + @as(u16, @intCast(index)) * geometry.overlay_row_step, .width = 640, .height = geometry.overlay_row_height };
    }
};

fn overlayFrame(result: *Tree, title: []const u8, context: []const u8, game_title: []const u8) void {
    const theme = result.theme;
    result.preserve_background = true;
    result.add(.{ .scrim = .{ .bounds = .{ .x = 0, .y = 0, .width = geometry.width, .height = geometry.height }, .color = theme.scrim, .alpha = 180 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = geometry.overlay_x, .y = geometry.overlay_y, .width = geometry.overlay_width, .height = geometry.overlay_height }, .color = theme.background, .radius = geometry.radius } });
    textLabel(result, .{ .x = 200, .y = 64, .width = 624, .height = 52 }, title, theme.text, font.title);
    result.add(.{ .text = .{ .bounds = .{ .x = 200, .y = 120, .width = 624, .height = 80 }, .value = game_title, .color = theme.muted, .font = font.caption, .lines = 2 } });
    if (context.len != 0) textLabel(result, .{ .x = 200, .y = 642, .width = 624, .height = 40 }, context, theme.accent, font.caption);
}

pub fn overlayPause(theme: Theme, game_title: []const u8, system: []const u8, selected: usize, state_slot: usize, saved: bool, performance: []const u8, notice: []const u8) Tree {
    const labels = [_][]const u8{ "Continue", "Save state", "Load state", "Performance", "Save and exit" };
    const slots = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3" };
    var result = Tree{ .theme = theme, .background = theme.background };
    overlayFrame(&result, "Game menu", notice, game_title);
    _ = system;
    for (labels, 0..) |label, index| {
        const resolved_detail = if (index == 1 and saved) "Saved" else "";
        result.add(.{ .overlay_row = .{
            .bounds = menu.overlayRow(index),
            .label = label,
            .detail = resolved_detail,
            .value = if (index == 1) slots[state_slot] else if (index == 3) performance else "",
            .selected = index == selected,
            .disclosure = index == 2,
        } });
    }
    hints(&result, .{ .x = 200, .y = 680, .width = 624, .height = 40 }, if (selected == 1)
        &.{ .{ .control = .horizontal, .label = "Slot" }, .{ .control = .confirm, .label = "Save" }, .{ .control = .back, .label = "Resume" } }
    else if (selected == 3)
        &.{ .{ .control = .horizontal, .label = "Change" }, .{ .control = .back, .label = "Resume" } }
    else
        &.{ .{ .control = .confirm, .label = "Select" }, .{ .control = .back, .label = "Resume" } });
    return result;
}

pub fn overlayStates(theme: Theme, game_title: []const u8, selected: usize, notice: []const u8, available: [4]bool) Tree {
    const labels = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3", "Automatic save" };
    const details = [_][]const u8{ "Manual save", "Manual save", "Manual save", "Latest session" };
    var result = Tree{ .theme = theme, .background = theme.background };
    overlayFrame(&result, "Load a save", notice, game_title);
    for (labels, details, 0..) |label, detail, index| {
        result.add(.{ .overlay_row = .{
            .bounds = menu.overlayRow(index),
            .label = label,
            .detail = if (available[index]) detail else "Empty",
            .selected = index == selected,
            .disclosure = false,
        } });
    }
    hints(&result, .{ .x = 200, .y = 680, .width = 624, .height = 40 }, &.{ .{ .control = .confirm, .label = "Load" }, .{ .control = .back, .label = "Back" }, .{ .control = .menu, .label = "Resume" } });
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
        .view, .menu => geometry.glyph_size,
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
        .view, .menu => {
            // The upper controls are narrow pills; the lower row has round keys.
            const upper = item.control == .view;
            const count: u16 = if (upper) 2 else 3;
            const key_width: u16 = if (upper) 28 else 18;
            const key_height: u16 = if (upper) 12 else 18;
            const gap: u16 = if (upper) 8 else 5;
            for (0..count) |index| {
                const bounds = Rect{ .x = x + @as(u16, @intCast(index)) * (key_width + gap), .y = y + (40 - key_height) / 2, .width = key_width, .height = key_height };
                result.add(.{ .bar = .{ .bounds = bounds, .color = colour, .radius = key_height / 2 } });
                if (index != 0) result.add(.{ .bar = .{
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
    const cell = @min(geometry.glyph_size + geometry.hint_gap + 128, bounds.width / @as(u16, @intCast(items.len)));
    for (items, 0..) |item, index| hint(result, bounds.x + @as(u16, @intCast(index)) * cell, bounds.y, cell - geometry.glyph_size - geometry.hint_gap, item);
}

fn footer(result: *Tree, items: []const Hint) void {
    hints(result, .{ .x = layout.margin, .y = layout.footer_y, .width = geometry.width - 2 * layout.margin, .height = 44 }, items);
}

fn artwork(result: *Tree, game: catalog.Game, bounds: Rect, cart: bool, dim: u8, tilt: i16) void {
    const sprite = if (cart) game.assets.card orelse game.assets.sprite else game.assets.cover;
    if (sprite == null and game.assets.preview == null) {
        result.add(.{ .bar = .{ .bounds = bounds, .color = result.theme.surface, .radius = geometry.radius } });
        result.add(.{ .text = .{ .bounds = .{ .x = bounds.x + 16, .y = bounds.y + bounds.height / 4, .width = bounds.width -| 32, .height = @min(120, bounds.height / 2) }, .value = game.title, .color = result.theme.text, .font = font.body, .lines = 2 } });
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
    title_font.line_height = 44;
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 568, .width = 880, .height = 88 }, .value = game.title, .color = result.theme.text, .font = title_font, .lines = 2 } });
    var system_font = font.caption;
    system_font.alignment = .center;
    textLabel(result, .{ .x = 72, .y = 660, .width = 880, .height = 38 }, game.system, result.theme.muted, system_font);
}

fn selectedTitle(result: *Tree, game: catalog.Game, bounds: Rect) void {
    const theme = result.theme;
    result.add(.{ .text = .{ .bounds = bounds, .value = game.title, .color = theme.text, .font = font.body, .lines = 2 } });
}

pub fn home(theme: Theme, selected: usize) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Brick");
    const items = [_][]const u8{ "Games", "Settings" };
    for (items, 0..) |item, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = layout.margin, .y = geometry.home_top + @as(u16, @intCast(index)) * geometry.home_step, .width = 944, .height = geometry.home_height },
        .label = item,
        .detail = if (index == 0) "Browse and play" else "Display, power and appearance",
        .selected = index == selected,
    } });
    footer(&result, &.{ .{ .control = .confirm, .label = "Open" }, .{ .control = .back, .label = "Games" } });
    return result;
}

pub fn library(theme: Theme, games: []const catalog.Game, selected: usize, view: LibraryView, shelf_offset: i16) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Games");
    if (games.len == 0) {
        textLabel(&result, .{ .x = 40, .y = 180, .width = 900, .height = 58 }, "No games yet", theme.text, font.title);
        textLabel(&result, .{ .x = 40, .y = 256, .width = 900, .height = 44 }, "Add games to the Roms folder on your SD card.", theme.muted, font.caption);
        footer(&result, &.{.{ .control = .menu, .label = "Menu" }});
        return result;
    }
    const game = games[selected];
    var view_font = font.caption;
    view_font.alignment = .end;
    textLabel(&result, .{ .x = 704, .y = 32, .width = 280, .height = 40 }, switch (view) {
        .list => "List",
        .grid => "Grid",
        .shelf => "Cartridge Flow",
    }, theme.muted, view_font);
    switch (view) {
        .list => {
            const visible = @min(games.len, 5);
            const first = if (selected > 1) @min(selected - 1, games.len - visible) else 0;
            for (games[first .. first + visible], first..) |entry, index| result.add(.{ .menu_row = .{
                .bounds = .{ .x = 32, .y = 112 + @as(u16, @intCast(index - first)) * 112, .width = 616, .height = 104 },
                .label = entry.title,
                .selected = index == selected,
                .disclosure = false,
                .lines = 2,
            } });
            artwork(&result, game, .{ .x = 688, .y = 128, .width = 296, .height = 408 }, false, 0, 0);
            var system_font = font.caption;
            system_font.alignment = .center;
            textLabel(&result, .{ .x = 680, .y = 560, .width = 312, .height = 80 }, game.system, theme.muted, system_font);
        },
        .grid => {
            const columns = geometry.grid_columns;
            const count = columns * geometry.grid_rows;
            const first = (selected / count) * count;
            for (games[first..@min(first + count, games.len)], 0..) |entry, index| {
                const x: u16 = 40 + @as(u16, @intCast(index % columns)) * 320;
                const y: u16 = 104 + @as(u16, @intCast(index / columns)) * 232;
                const active = first + index == selected;
                result.add(.{ .bar = .{ .bounds = .{ .x = x, .y = y, .width = 304, .height = 216 }, .color = if (active) theme.accent else theme.surface, .radius = geometry.radius } });
                result.add(.{ .bar = .{ .bounds = .{ .x = x + 4, .y = y + 4, .width = 296, .height = 208 }, .color = theme.surface, .radius = geometry.radius - 4 } });
                artwork(&result, entry, .{ .x = x + 20, .y = y + 12, .width = 264, .height = 192 }, false, 0, 0);
            }
            caption(&result, game);
        },
        .shelf => {
            const order = [_]i8{ -4, 4, -3, 3, -2, 2, -1, 1, 0 };
            for (order) |relative| {
                const index = @as(i64, @intCast(selected)) + relative;
                if (index < 0 or index >= games.len) continue;
                const pose = shelfPose(relative, shelf_offset);
                artwork(&result, games[@intCast(index)], pose.bounds, true, pose.dim, pose.tilt);
                if (result.elements[result.len - 1] == .cartridge)
                    result.elements[result.len - 1].cartridge.clip_left = pose.clip_left;
            }
            caption(&result, game);
        },
    }
    footer(&result, &.{ .{ .control = .confirm, .label = "Play" }, .{ .control = .view, .label = "View" }, .{ .control = .menu, .label = "Menu" } });
    return result;
}

const ShelfPose = struct { bounds: Rect, dim: u8, tilt: i16, clip_left: u16 };

fn shelfPose(relative: i8, offset: i16) ShelfPose {
    const position = @as(i32, relative) * 1000 + offset;
    const distance = @abs(position);
    // Keep the focused cartridge large, then overlap the three neighbours on
    // each side. The fourth is offscreen, ready for a continuous transition.
    const center = 512 + @divTrunc(position * geometry.shelf_step, 1000) + @divTrunc(@max(-1000, @min(1000, position)) * 104, 1000);
    const width: i32 = if (distance < 1000) 480 - @as(i32, @intCast(distance * 260 / 1000)) else 220;
    const height: i32 = if (distance < 1000) 440 - @as(i32, @intCast(distance * 120 / 1000)) else 320;
    return .{
        .bounds = .{ .x = @intCast(@max(0, center - @divTrunc(width, 2))), .y = @intCast(104 + @divTrunc(440 - height, 2)), .width = @intCast(width), .height = @intCast(height) },
        .clip_left = @intCast(@max(0, @divTrunc(width, 2) - center)),
        .dim = @intCast(@min(120, distance * 50 / 1000)),
        .tilt = @intCast(@max(-1000, @min(1000, position))),
    };
}

pub fn gameDetail(theme: Theme, game: catalog.Game, launch_failed: ?[]const u8) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, if (launch_failed != null) "Unable to start" else "Game");
    artwork(&result, game, .{ .x = 40, .y = 156, .width = 280, .height = 416 }, false, 0, 0);
    textLabel(&result, .{ .x = 368, .y = 162, .width = 616, .height = 44 }, game.system, theme.muted, font.caption);
    selectedTitle(&result, game, .{ .x = 368, .y = 222, .width = 616, .height = 144 });
    if (launch_failed) |message| textLabel(&result, .{ .x = 368, .y = 410, .width = 616, .height = 80 }, message, theme.danger, font.caption);
    footer(&result, &.{ .{ .control = .confirm, .label = if (launch_failed != null) "Retry" else "Play" }, .{ .control = .back, .label = "Games" } });
    return result;
}

pub fn settings(selected: usize, values: settings_model.Values) Tree {
    const theme = values.appearance.colors();
    const items = [_][]const u8{ "Brightness", "Performance", "Screen off", "Suspend", "Appearance" };
    const details = [_][]const u8{ values.value(.brightness), values.value(.performance), values.value(.display_timeout), values.value(.suspend_timeout), values.value(.appearance) };
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Settings");
    for (items, details, 0..) |item, value, index| result.add(.{ .overlay_row = .{
        .bounds = .{ .x = 40, .y = geometry.settings_top + @as(u16, @intCast(index)) * geometry.settings_step, .width = geometry.width - 2 * layout.margin, .height = geometry.settings_height },
        .label = item,
        .detail = "",
        .value = value,
        .selected = index == selected,
        .disclosure = false,
    } });
    footer(&result, &.{ .{ .control = .horizontal, .label = "Change" }, .{ .control = .back, .label = "Back" } });
    return result;
}

pub fn splash(theme: Theme) Tree {
    var result = Tree{ .theme = theme, .background = theme.scrim };
    result.add(.{ .bar = .{ .bounds = .{ .x = 438, .y = 246, .width = 68, .height = 68 }, .color = theme.accent } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 518, .y = 246, .width = 68, .height = 68 }, .color = theme.selection } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 438, .y = 326, .width = 148, .height = 68 }, .color = theme.on_scrim } });
    result.add(.{ .text = .{ .bounds = .{ .x = 424, .y = 442, .width = 240, .height = 72 }, .value = "Brick", .color = theme.on_scrim, .font = font.brand } });
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

pub fn showNotice(tree: *Tree, message: []const u8) void {
    tree.add(.{ .bar = .{ .bounds = .{ .x = layout.margin, .y = layout.footer_y, .width = geometry.width - 2 * layout.margin, .height = 44 }, .color = tree.theme.background } });
    textLabel(tree, .{ .x = layout.margin, .y = layout.footer_y, .width = geometry.width - 2 * layout.margin, .height = 44 }, message, tree.theme.danger, font.control);
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
