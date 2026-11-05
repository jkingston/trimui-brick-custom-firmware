// SPDX-License-Identifier: GPL-2.0-only
const catalog = @import("catalog.zig");
const settings_model = @import("settings.zig");

pub const Color = @import("color.zig").Color;
pub const Theme = @import("theme.zig").Theme;

pub const Rect = struct { x: u16, y: u16, width: u16, height: u16 };
pub const Text = struct { bounds: Rect, value: []const u8, color: Color, scale: u8 = 3, language: []const u8 = "", lines: u8 = 1 };
pub const Bar = struct { bounds: Rect, color: Color };
pub const Scrim = struct { bounds: Rect, color: Color, alpha: u8 };
pub const MenuRow = struct {
    bounds: Rect,
    label: []const u8,
    detail: []const u8 = "",
    selected: bool,
    disclosure: bool = true,
};
pub const Battery = struct { bounds: Rect, percent: u8 };
pub const Cover = struct { bounds: Rect, kind: catalog.Cover };
pub const LibraryView = enum { list, shelf, grid };
pub const Cartridge = struct {
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
        self.elements[self.len] = element;
        self.len += 1;
    }

    pub fn slice(self: *const Tree) []const Element {
        return self.elements[0..self.len];
    }
};

pub const palette = struct {
    pub const white = Color{ .r = 0xff, .g = 0xfe, .b = 0xf9 };
    pub const paper = Color{ .r = 0xf3, .g = 0xf1, .b = 0xe9 };
    pub const surface = Color{ .r = 0xe7, .g = 0xe9, .b = 0xdf };
    pub const selected = Color{ .r = 0xd8, .g = 0xe5, .b = 0xdc };
    pub const chrome = Color{ .r = 0xcb, .g = 0xd0, .b = 0xc8 };
    pub const chrome_dark = Color{ .r = 0x9d, .g = 0xa8, .b = 0xa0 };
    pub const ink = Color{ .r = 0x14, .g = 0x21, .b = 0x1b };
    pub const quiet = Color{ .r = 0x66, .g = 0x71, .b = 0x69 };
    pub const pine = Color{ .r = 0x23, .g = 0x6a, .b = 0x53 };
    pub const deep = Color{ .r = 0x10, .g = 0x28, .b = 0x20 };
    pub const blue = pine;
    pub const blue_dark = deep;
    pub const navy = Color{ .r = 0x13, .g = 0x25, .b = 0x3c };
    pub const sky = Color{ .r = 0x73, .g = 0xc8, .b = 0xea };
    pub const coral = Color{ .r = 0xe7, .g = 0x5c, .b = 0x4c };
    pub const gold = Color{ .r = 0xf2, .g = 0xb9, .b = 0x3b };
    pub const green = Color{ .r = 0x4e, .g = 0xa6, .b = 0x68 };
};

const menu = struct {
    fn row(index: usize) Rect {
        return .{ .x = 32, .y = 148 + @as(u16, @intCast(index)) * 108, .width = 418, .height = 96 };
    }
    fn overlayRow(index: usize) Rect {
        return .{ .x = 486, .y = 176 + @as(u16, @intCast(index)) * 96, .width = 458, .height = 86 };
    }
};

fn gameCaption(result: *Tree, title: []const u8, system: []const u8) void {
    const theme = result.theme;
    result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 636, .width = 390, .height = 44 }, .value = title, .color = theme.on_scrim, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 684, .width = 350, .height = 34 }, .value = system, .color = theme.border, .scale = 2 } });
}

fn overlayFrame(result: *Tree, title: []const u8, context: []const u8, game_title: []const u8, system: []const u8) void {
    const theme = result.theme;
    result.preserve_background = true;
    result.add(.{ .scrim = .{ .bounds = .{ .x = 0, .y = 0, .width = 1024, .height = 768 }, .color = theme.scrim, .alpha = 126 } });
    gameCaption(result, game_title, system);
    result.add(.{ .bar = .{ .bounds = .{ .x = 456, .y = 48, .width = 536, .height = 680 }, .color = theme.scrim } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 446, .y = 38, .width = 536, .height = 680 }, .color = theme.background } });
    result.add(.{ .text = .{ .bounds = .{ .x = 486, .y = 70, .width = 430, .height = 58 }, .value = title, .color = theme.text, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 488, .y = 128, .width = 420, .height = 34 }, .value = context, .color = theme.muted, .scale = 2 } });
}

pub fn overlayPause(theme: Theme, game_title: []const u8, system: []const u8, selected: usize, state_slot: usize, saved: bool, performance: []const u8, notice: []const u8) Tree {
    const labels = [_][]const u8{ "Continue", "Save state", "Load state", "Performance", "Save and exit" };
    const slots = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3" };
    var result = Tree{ .theme = theme, .background = theme.background };
    overlayFrame(&result, "Paused", if (notice.len != 0) notice else system, game_title, "");
    for (labels, 0..) |label, index| {
        const resolved_detail = if (index == 1)
            (if (saved) "Saved just now" else if (selected == index) "Left/right changes slot" else "")
        else if (index == 2)
            "Choose a save"
        else if (index == 3)
            (if (selected == index) "Left/right changes value" else "")
        else if (index == 4)
            "Auto-saves first"
        else
            "";
        result.add(.{ .overlay_row = .{
            .bounds = menu.overlayRow(index),
            .label = label,
            .detail = resolved_detail,
            .value = if (index == 1) slots[state_slot] else if (index == 3) performance else "",
            .selected = index == selected,
            .disclosure = index == 2,
        } });
    }
    textLabel(&result, .{ .x = 486, .y = 674, .width = 458, .height = 40 }, if (selected == 1) "← / → Slot   A Save   B Back" else if (selected == 3) "← / → Change   B Back" else "A Select   B Continue", theme.muted, 2);
    return result;
}

pub fn overlayStates(theme: Theme, game_title: []const u8, selected: usize, notice: []const u8, available: [4]bool) Tree {
    const labels = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3", "Automatic save" };
    const details = [_][]const u8{ "Manual save", "Manual save", "Manual save", "Latest session" };
    var result = Tree{ .theme = theme, .background = theme.background };
    overlayFrame(&result, "Load a save", if (notice.len == 0) "Select a save slot" else notice, game_title, "");
    for (labels, details, 0..) |label, detail, index| {
        result.add(.{ .overlay_row = .{
            .bounds = menu.overlayRow(index),
            .label = label,
            .detail = if (available[index]) detail else "Empty",
            .selected = index == selected,
            .disclosure = false,
        } });
    }
    result.add(.{ .text = .{ .bounds = .{ .x = 488, .y = 674, .width = 430, .height = 34 }, .value = "A Load    B Back    Menu Resume", .color = theme.muted, .scale = 2 } });
    return result;
}

const layout = struct {
    const margin = 40;
    const footer_y = 704;
};

fn textLabel(result: *Tree, bounds: Rect, value: []const u8, color: Color, scale: u8) void {
    result.add(.{ .text = .{ .bounds = bounds, .value = value, .color = color, .scale = scale } });
}

fn header(result: *Tree, title: []const u8) void {
    const theme = result.theme;
    textLabel(result, .{ .x = layout.margin, .y = 28, .width = 800, .height = 58 }, title, theme.text, 4);
    result.add(.{ .bar = .{ .bounds = .{ .x = layout.margin, .y = 100, .width = 944, .height = 2 }, .color = theme.border } });
}

fn footer(result: *Tree, actions: []const u8) void {
    const theme = result.theme;
    result.add(.{ .bar = .{ .bounds = .{ .x = layout.margin, .y = layout.footer_y - 16, .width = 944, .height = 2 }, .color = theme.border } });
    textLabel(result, .{ .x = layout.margin, .y = layout.footer_y, .width = 944, .height = 44 }, actions, theme.muted, 2);
}

fn artwork(result: *Tree, game: catalog.Game, bounds: Rect, cart: bool, dim: u8, tilt: i16) void {
    result.add(.{ .cartridge = .{
        .bounds = bounds,
        .platform = game.platform_id,
        .texture = game.assets.preview,
        .sprite = if (cart) game.assets.card orelse game.assets.sprite else game.assets.cover,
        .selected = true,
        .dim = dim,
        .tilt = tilt,
        .plain_fallback = !cart,
    } });
}

fn selectedTitle(result: *Tree, game: catalog.Game, bounds: Rect) void {
    const theme = result.theme;
    result.add(.{ .text = .{ .bounds = bounds, .value = game.title, .color = theme.text, .scale = 3, .lines = 2 } });
}

pub fn home(theme: Theme, selected: usize) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Menu");
    const items = [_][]const u8{ "Games", "Settings" };
    for (items, 0..) |item, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = layout.margin, .y = 140 + @as(u16, @intCast(index)) * 104, .width = 944, .height = 92 },
        .label = item,
        .selected = index == selected,
    } });
    footer(&result, "A  Open     B  Games");
    return result;
}

pub fn library(theme: Theme, games: []const catalog.Game, selected: usize, view: LibraryView, shelf_offset: i16) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Games");
    if (games.len == 0) {
        textLabel(&result, .{ .x = 40, .y = 180, .width = 900, .height = 58 }, "No games yet", theme.text, 4);
        textLabel(&result, .{ .x = 40, .y = 256, .width = 900, .height = 44 }, "Add games to the Roms folder on your SD card.", theme.muted, 2);
        footer(&result, "Menu  Settings");
        return result;
    }
    const game = games[selected];
    textLabel(&result, .{ .x = 40, .y = 114, .width = 700, .height = 40 }, game.system, theme.muted, 2);
    textLabel(&result, .{ .x = 820, .y = 114, .width = 164, .height = 40 }, switch (view) {
        .list => "List",
        .grid => "Grid",
        .shelf => "Shelf",
    }, theme.muted, 2);
    switch (view) {
        .list => {
            const first = if (selected > 1) @min(selected - 1, games.len - @min(games.len, 4)) else 0;
            for (games[first..@min(first + 4, games.len)], first..) |entry, index| result.add(.{ .menu_row = .{
                .bounds = .{ .x = 40, .y = 170 + @as(u16, @intCast(index - first)) * 84, .width = 604, .height = 80 },
                .label = entry.title,
                .selected = index == selected,
                .disclosure = false,
            } });
            artwork(&result, game, .{ .x = 692, .y = 174, .width = 252, .height = 332 }, false, 0, 0);
            selectedTitle(&result, game, .{ .x = 40, .y = 546, .width = 944, .height = 120 });
        },
        .grid => {
            const first = (selected / 4) * 4;
            for (games[first..@min(first + 4, games.len)], 0..) |entry, index| {
                const x: u16 = 40 + @as(u16, @intCast(index)) * 240;
                const active = first + index == selected;
                if (active) result.add(.{ .bar = .{ .bounds = .{ .x = x, .y = 166, .width = 224, .height = 342 }, .color = theme.selection } });
                artwork(&result, entry, .{ .x = x + 16, .y = 182, .width = 192, .height = 304 }, false, 0, 0);
                if (active) result.add(.{ .bar = .{ .bounds = .{ .x = x, .y = 504, .width = 224, .height = 4 }, .color = theme.accent } });
            }
            selectedTitle(&result, game, .{ .x = 40, .y = 546, .width = 944, .height = 120 });
        },
        .shelf => {
            const order = [_]i8{ -4, 4, -3, 3, -2, 2, -1, 1, 0 };
            for (order) |relative| {
                const index = @as(i64, @intCast(selected)) + relative;
                if (index < 0 or index >= games.len) continue;
                const pose = shelfPose(relative, shelf_offset);
                artwork(&result, games[@intCast(index)], pose.bounds, true, pose.dim, pose.tilt);
                result.elements[result.len - 1].cartridge.clip_left = pose.clip_left;
            }
            selectedTitle(&result, game, .{ .x = 40, .y = 568, .width = 944, .height = 104 });
        },
    }
    footer(&result, "A  Play     F1  View     Menu  Options");
    return result;
}

const ShelfPose = struct { bounds: Rect, dim: u8, tilt: i16, clip_left: u16 };

fn shelfPose(relative: i8, offset: i16) ShelfPose {
    const position = @as(i32, relative) * 1000 + offset;
    const distance = @abs(position);
    const center = 512 + @divTrunc(position * 274, 1000);
    const width: i32 = if (distance < 1000) 440 - @as(i32, @intCast(distance * 240 / 1000)) else 200;
    const height: i32 = if (distance < 1000) 400 - @as(i32, @intCast(distance * 104 / 1000)) else 296;
    return .{
        .bounds = .{ .x = @intCast(@max(0, center - @divTrunc(width, 2))), .y = @intCast(160 + @divTrunc(400 - height, 2)), .width = @intCast(width), .height = @intCast(height) },
        .clip_left = @intCast(@max(0, @divTrunc(width, 2) - center)),
        .dim = @intCast(@min(120, distance * 50 / 1000)),
        .tilt = @intCast(@max(-1000, @min(1000, position))),
    };
}

pub fn gameDetail(theme: Theme, game: catalog.Game, launch_failed: ?[]const u8) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, if (launch_failed != null) "Unable to start" else "Game");
    artwork(&result, game, .{ .x = 40, .y = 156, .width = 280, .height = 416 }, false, 0, 0);
    textLabel(&result, .{ .x = 368, .y = 162, .width = 616, .height = 44 }, game.system, theme.muted, 2);
    selectedTitle(&result, game, .{ .x = 368, .y = 222, .width = 616, .height = 144 });
    if (launch_failed) |message| textLabel(&result, .{ .x = 368, .y = 410, .width = 616, .height = 80 }, message, theme.danger, 2);
    footer(&result, if (launch_failed != null) "A  Retry     B  Games" else "A  Play     B  Games");
    return result;
}

pub fn settings(selected: usize, values: settings_model.Values) Tree {
    const theme = values.appearance.colors();
    const items = [_][]const u8{ "Brightness", "Performance", "Screen off", "Suspend", "Appearance" };
    const details = [_][]const u8{ values.value(.brightness), values.value(.performance), values.value(.display_timeout), values.value(.suspend_timeout), values.value(.appearance) };
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Settings");
    for (items, details, 0..) |item, value, index| result.add(.{ .overlay_row = .{
        .bounds = .{ .x = 40, .y = 144 + @as(u16, @intCast(index)) * 104, .width = 944, .height = 96 },
        .label = item,
        .detail = "",
        .value = value,
        .selected = index == selected,
        .disclosure = false,
    } });
    footer(&result, "Left / Right  Change     B  Back");
    return result;
}

pub fn splash(theme: Theme) Tree {
    var result = Tree{ .theme = theme, .background = theme.scrim };
    result.add(.{ .bar = .{ .bounds = .{ .x = 438, .y = 246, .width = 68, .height = 68 }, .color = theme.accent } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 518, .y = 246, .width = 68, .height = 68 }, .color = theme.selection } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 438, .y = 326, .width = 148, .height = 68 }, .color = theme.on_scrim } });
    result.add(.{ .text = .{ .bounds = .{ .x = 424, .y = 442, .width = 240, .height = 72 }, .value = "Brick", .color = theme.on_scrim, .scale = 6 } });
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
    result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 96, .width = 420, .height = 34 }, .value = "Shaping and fallback", .color = theme.accent, .scale = 2 } });
    for (left, left_languages, 0..) |sample, language, index|
        result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 150 + @as(u16, @intCast(index)) * 76, .width = 438, .height = 48 }, .value = sample, .color = theme.text, .scale = 2, .language = language } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 510, .y = 118, .width = 2, .height = 590 }, .color = theme.border } });
    for (right, right_languages, 0..) |sample, language, index|
        result.add(.{ .text = .{ .bounds = .{ .x = 544, .y = 126 + @as(u16, @intCast(index)) * 70, .width = 438, .height = 48 }, .value = sample, .color = theme.text, .scale = 2, .language = language } });
    return result;
}
