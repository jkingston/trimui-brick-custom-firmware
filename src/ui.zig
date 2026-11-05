// SPDX-License-Identifier: GPL-2.0-only
const catalog = @import("catalog.zig");
const settings_model = @import("settings.zig");

pub const Color = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    a: u8 = 0xff,
};

pub const Rect = struct { x: u16, y: u16, width: u16, height: u16 };
pub const Text = struct { bounds: Rect, value: []const u8, color: Color, scale: u8 = 3, language: []const u8 = "" };
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
    selected: bool = false,
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
    result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 636, .width = 390, .height = 44 }, .value = title, .color = palette.white, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 684, .width = 350, .height = 34 }, .value = system, .color = palette.chrome, .scale = 2 } });
}

fn overlayFrame(result: *Tree, title: []const u8, context: []const u8, game_title: []const u8, system: []const u8) void {
    result.preserve_background = true;
    result.add(.{ .scrim = .{ .bounds = .{ .x = 0, .y = 0, .width = 1024, .height = 768 }, .color = palette.deep, .alpha = 126 } });
    gameCaption(result, game_title, system);
    result.add(.{ .bar = .{ .bounds = .{ .x = 456, .y = 48, .width = 536, .height = 680 }, .color = palette.deep } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 446, .y = 38, .width = 536, .height = 680 }, .color = palette.paper } });
    result.add(.{ .text = .{ .bounds = .{ .x = 486, .y = 70, .width = 430, .height = 58 }, .value = title, .color = palette.ink, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 488, .y = 128, .width = 420, .height = 34 }, .value = context, .color = palette.quiet, .scale = 2 } });
    result.add(.{ .battery = .{ .bounds = .{ .x = 914, .y = 76, .width = 48, .height = 20 }, .percent = 82 } });
}

pub fn overlayPause(game_title: []const u8, system: []const u8, selected: usize, state_slot: usize, saved: bool, performance: []const u8) Tree {
    const labels = [_][]const u8{ "Continue", "Save state", "Load state", "Performance", "Save and exit" };
    const slots = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3" };
    var result = Tree{ .background = palette.paper };
    overlayFrame(&result, "Paused", game_title, game_title, system);
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
    return result;
}

pub fn overlayStates(game_title: []const u8, selected: usize, notice: []const u8) Tree {
    const labels = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3", "Automatic save" };
    const details = [_][]const u8{ "Manual save", "Manual save", "Manual save", "Latest session" };
    var result = Tree{ .background = palette.paper };
    overlayFrame(&result, "Load a save", if (notice.len == 0) "Choose a moment to restore" else notice, game_title, "");
    for (labels, details, 0..) |label, detail, index| {
        result.add(.{ .overlay_row = .{
            .bounds = menu.overlayRow(index),
            .label = label,
            .detail = detail,
            .selected = index == selected,
            .disclosure = false,
        } });
    }
    result.add(.{ .text = .{ .bounds = .{ .x = 488, .y = 674, .width = 430, .height = 34 }, .value = "A Load    B Back    Menu Resume", .color = palette.quiet, .scale = 2 } });
    return result;
}

fn header(result: *Tree, title: []const u8) void {
    result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 0, .width = 1024, .height = 72 }, .color = palette.paper } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 32, .y = 70, .width = 960, .height = 2 }, .color = palette.chrome } });
    result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 14, .width = 360, .height = 48 }, .value = title, .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 824, .y = 22, .width = 84, .height = 34 }, .value = "12:42", .color = palette.quiet, .scale = 2 } });
    result.add(.{ .battery = .{ .bounds = .{ .x = 938, .y = 24, .width = 46, .height = 22 }, .percent = 82 } });
}

pub fn home(selected: usize) Tree {
    const items = [_][]const u8{ "Games", "Recent", "Favorites", "Settings" };
    const preview_titles = [_][]const u8{ "Your library", "Minekart Madness", "Eight favorites", "Device settings" };
    const preview_details = [_][]const u8{ "5 systems  /  142 games", "NES  /  Played yesterday", "Ready when you are", "Display, audio, power" };
    const preview_actions = [_][]const u8{ "A  Browse games", "A  Resume game", "A  View favorites", "A  Open settings" };
    const preview_covers = [_]catalog.Cover{ .library, .minekart, .adjustris, .library };
    var result = Tree{ .background = palette.paper };
    header(&result, "Home");
    result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 96, .width = 320, .height = 34 }, .value = "Library", .color = palette.pine, .scale = 2 } });
    for (items, 0..) |label, index| {
        result.add(.{ .menu_row = .{
            .bounds = menu.row(index),
            .label = label,
            .selected = index == selected,
        } });
    }
    result.add(.{ .bar = .{ .bounds = .{ .x = 480, .y = 104, .width = 512, .height = 624 }, .color = palette.deep } });
    result.add(.{ .text = .{ .bounds = .{ .x = 520, .y = 132, .width = 300, .height = 34 }, .value = if (selected == 1) "Continue" else "Selected", .color = palette.chrome, .scale = 2 } });
    result.add(.{ .cover = .{ .bounds = .{ .x = 604, .y = 184, .width = 264, .height = 264 }, .kind = preview_covers[selected] } });
    result.add(.{ .text = .{ .bounds = .{ .x = 520, .y = 492, .width = 430, .height = 52 }, .value = preview_titles[selected], .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 522, .y = 554, .width = 410, .height = 34 }, .value = preview_details[selected], .color = palette.chrome, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 522, .y = 652, .width = 410, .height = 44 }, .value = preview_actions[selected], .color = palette.white, .scale = 3 } });
    return result;
}

pub fn library(games: []const catalog.Game, selected: usize, view: LibraryView, shelf_offset: i16) Tree {
    var result = Tree{ .background = palette.paper };
    header(&result, "Games");
    result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 96, .width = 360, .height = 34 }, .value = "All systems", .color = palette.quiet, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 846, .y = 96, .width = 140, .height = 34 }, .value = "F1  View", .color = palette.pine, .scale = 2 } });
    if (games.len == 0) {
        result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 176, .width = 460, .height = 48 }, .value = "No games found", .color = palette.ink, .scale = 3 } });
        result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 232, .width = 500, .height = 34 }, .value = "Copy games to the Roms folder", .color = palette.quiet, .scale = 2 } });
        return result;
    }
    if (view == .shelf) {
        const positions = [_]Rect{
            .{ .x = 38, .y = 174, .width = 190, .height = 300 },
            .{ .x = 220, .y = 174, .width = 190, .height = 300 },
            .{ .x = 402, .y = 174, .width = 190, .height = 300 },
            .{ .x = 584, .y = 174, .width = 190, .height = 300 },
            .{ .x = 766, .y = 174, .width = 190, .height = 300 },
        };
        for (positions, 0..) |position, index| {
            if (index < 2 and selected < 2 - index) continue;
            const game_index = if (index < 2) selected - (2 - index) else selected + (index - 2);
            if (game_index >= games.len) continue;
            const game = games[game_index];
            result.add(.{ .cartridge = .{
                .bounds = .{
                    .x = @intCast(@max(0, @as(i32, position.x) + shelf_offset)),
                    .y = position.y,
                    .width = position.width,
                    .height = position.height,
                },
                .platform = game.platform_id,
                .texture = game.assets.preview,
                .selected = game_index == selected,
            } });
        }
        const game = games[selected];
        result.add(.{ .text = .{ .bounds = .{ .x = 170, .y = 550, .width = 684, .height = 56 }, .value = game.title, .color = palette.ink, .scale = 4 } });
        result.add(.{ .text = .{ .bounds = .{ .x = 280, .y = 614, .width = 464, .height = 34 }, .value = game.system, .color = palette.pine, .scale = 2 } });
        result.add(.{ .text = .{ .bounds = .{ .x = 374, .y = 690, .width = 300, .height = 34 }, .value = "A  Open", .color = palette.pine, .scale = 2 } });
        return result;
    }
    if (view == .grid) {
        const first = (selected / 8) * 8;
        for (games[first..@min(first + 8, games.len)], 0..) |game, index| {
            const column: u16 = @intCast(index % 4);
            const row: u16 = @intCast(index / 4);
            result.add(.{ .cartridge = .{
                .bounds = .{ .x = 64 + column * 242, .y = 138 + row * 286, .width = 154, .height = 190 },
                .platform = game.platform_id,
                .texture = game.assets.preview,
                .selected = first + index == selected,
            } });
            result.add(.{ .text = .{
                .bounds = .{ .x = 40 + column * 242, .y = 340 + row * 286, .width = 210, .height = 34 },
                .value = game.title,
                .color = if (first + index == selected) palette.pine else palette.ink,
                .scale = 2,
            } });
        }
        return result;
    }
    const first = if (selected >= 5) selected - 4 else 0;
    for (games[first..@min(first + 5, games.len)], first..) |game, index| {
        result.add(.{ .menu_row = .{
            .bounds = menu.row(index - first),
            .label = game.title,
            .detail = game.system,
            .selected = index == selected,
        } });
    }
    const game = games[selected];
    result.add(.{ .cartridge = .{
        .bounds = .{ .x = 590, .y = 118, .width = 336, .height = 336 },
        .platform = game.platform_id,
        .texture = game.assets.preview,
        .selected = true,
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 520, .y = 494, .width = 454, .height = 52 }, .value = game.title, .color = palette.ink, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 522, .y = 554, .width = 430, .height = 34 }, .value = game.system, .color = palette.pine, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 522, .y = 596, .width = 430, .height = 34 }, .value = game.summary, .color = palette.quiet, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 522, .y = 682, .width = 340, .height = 34 }, .value = "A  Open", .color = palette.pine, .scale = 2 } });
    return result;
}

pub fn gameDetail(game: catalog.Game, launch_failed: ?[]const u8) Tree {
    var result = Tree{ .background = palette.paper };
    header(&result, "Game");
    result.add(.{ .cartridge = .{
        .bounds = .{ .x = 54, .y = 126, .width = 410, .height = 410 },
        .platform = game.platform_id,
        .texture = game.assets.preview,
        .selected = true,
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 530, .y = 128, .width = 430, .height = 34 }, .value = game.system, .color = palette.pine, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 500, .y = 174, .width = 492, .height = 60 }, .value = game.title, .color = palette.ink, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 530, .y = 244, .width = 420, .height = 34 }, .value = game.summary, .color = palette.quiet, .scale = 2 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 528, .y = 320, .width = 424, .height = 92 }, .color = palette.pine } });
    result.add(.{ .text = .{ .bounds = .{ .x = 566, .y = 342, .width = 220, .height = 52 }, .value = "Play", .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 892, .y = 346, .width = 42, .height = 44 }, .value = "A", .color = palette.white, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 530, .y = 470, .width = 300, .height = 34 }, .value = "Last played", .color = palette.quiet, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 530, .y = 510, .width = 300, .height = 44 }, .value = "Yesterday", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 530, .y = 580, .width = 300, .height = 34 }, .value = "Latest save", .color = palette.quiet, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 530, .y = 620, .width = 360, .height = 44 }, .value = "Auto save available", .color = palette.ink, .scale = 3 } });
    if (launch_failed) |message|
        result.add(.{ .text = .{ .bounds = .{ .x = 530, .y = 690, .width = 440, .height = 34 }, .value = message, .color = palette.coral, .scale = 2 } });
    return result;
}

pub fn settings(selected: usize, values: settings_model.Values) Tree {
    const items = [_][]const u8{ "Brightness", "Performance", "Screen off", "Suspend", "About" };
    const descriptions = [_][]const u8{ "Display brightness", "Speed and battery balance", "Turn off the display when idle", "Enter deep sleep when idle", "System information" };
    const details = [_][]const u8{
        values.value(.brightness),      values.value(.performance), values.value(.display_timeout),
        values.value(.suspend_timeout), "Brick OS 0.1",
    };
    var result = Tree{ .background = palette.paper };
    header(&result, "Settings");
    result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 96, .width = 320, .height = 34 }, .value = "Device", .color = palette.pine, .scale = 2 } });
    for (items, 0..) |label, index| {
        result.add(.{ .menu_row = .{
            .bounds = menu.row(index),
            .label = label,
            .detail = details[index],
            .selected = index == selected,
        } });
    }
    result.add(.{ .bar = .{ .bounds = .{ .x = 488, .y = 128, .width = 472, .height = 300 }, .color = palette.surface } });
    result.add(.{ .text = .{ .bounds = .{ .x = 530, .y = 174, .width = 390, .height = 58 }, .value = items[selected], .color = palette.ink, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 532, .y = 244, .width = 380, .height = 34 }, .value = descriptions[selected], .color = palette.quiet, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 532, .y = 334, .width = 380, .height = 44 }, .value = details[selected], .color = palette.pine, .scale = 3 } });
    if (selected < 4)
        result.add(.{ .text = .{ .bounds = .{ .x = 532, .y = 384, .width = 380, .height = 34 }, .value = "LEFT / RIGHT TO CHANGE", .color = palette.quiet, .scale = 2 } });
    return result;
}

pub fn splash() Tree {
    var result = Tree{ .background = palette.deep };
    result.add(.{ .bar = .{ .bounds = .{ .x = 438, .y = 246, .width = 68, .height = 68 }, .color = palette.pine } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 518, .y = 246, .width = 68, .height = 68 }, .color = palette.selected } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 438, .y = 326, .width = 148, .height = 68 }, .color = palette.white } });
    result.add(.{ .text = .{ .bounds = .{ .x = 424, .y = 442, .width = 240, .height = 72 }, .value = "Brick", .color = palette.white, .scale = 6 } });
    return result;
}

pub fn languageProof() Tree {
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
    var result = Tree{ .background = palette.paper };
    header(&result, "Language proof");
    result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 96, .width = 420, .height = 34 }, .value = "Shaping and fallback", .color = palette.pine, .scale = 2 } });
    for (left, left_languages, 0..) |sample, language, index|
        result.add(.{ .text = .{ .bounds = .{ .x = 40, .y = 150 + @as(u16, @intCast(index)) * 76, .width = 438, .height = 48 }, .value = sample, .color = palette.ink, .scale = 2, .language = language } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 510, .y = 118, .width = 2, .height = 590 }, .color = palette.chrome } });
    for (right, right_languages, 0..) |sample, language, index|
        result.add(.{ .text = .{ .bounds = .{ .x = 544, .y = 126 + @as(u16, @intCast(index)) * 70, .width = 438, .height = 48 }, .value = sample, .color = palette.ink, .scale = 2, .language = language } });
    return result;
}
