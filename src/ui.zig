// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const design = @import("design.zig");
const font = design.typeface;
const geometry = design.geometry;
const catalog = @import("catalog.zig");
const interaction = @import("interaction.zig");
const bluetooth_model = @import("bluetooth.zig");
const scene = @import("ui_scene.zig");
const game_object = @import("game_object.zig");
pub const Color = scene.Color;
pub const Theme = scene.Theme;
pub const Rect = scene.Rect;
pub const Text = scene.Text;
pub const TextBlock = scene.TextBlock;
pub const FocusFrame = scene.FocusFrame;
pub const Bar = scene.Bar;
pub const Scrim = scene.Scrim;
pub const RowStyle = scene.RowStyle;
pub const ArtworkStyle = scene.ArtworkStyle;
pub const MenuRow = scene.MenuRow;
pub const ActionCard = scene.ActionCard;
pub const CardEmphasis = scene.CardEmphasis;
pub const Battery = scene.Battery;
pub const Meter = scene.Meter;
pub const Activity = scene.Activity;
pub const QrCode = scene.QrCode;
pub const Keyboard = scene.Keyboard;
pub const KeyboardKey = scene.KeyboardKey;
pub const Cover = scene.Cover;
/// One library with progressively denser ways to move through it. Names encode
/// the player's intent rather than the widget used to render the collection.
pub const LibraryView = enum { recent, browse, all };
pub const Cartridge = scene.Cartridge;
pub const OverlayRow = scene.OverlayRow;
pub const Element = scene.Element;
pub const Tree = scene.Tree;

fn controlTheme(source: Theme) Theme {
    var result = source;
    result.background = source.scrim;
    result.surface = .{ .r = 0x17, .g = 0x1c, .b = 0x1c };
    result.text = source.on_scrim;
    result.muted = .{ .r = 0x92, .g = 0x9b, .b = 0x99 };
    result.accent = .{ .r = 0x59, .g = 0xd4, .b = 0xcf };
    result.border = .{ .r = 0x34, .g = 0x3c, .b = 0x3b };
    result.focus_shadow = source.scrim;
    return result;
}

fn controlDeck(source_theme: Theme, scope: interaction.Id.Scope, title: []const u8, context: []const u8, labels: []const []const u8, values: []const []const u8, selected: usize, back_label: []const u8, action_label: []const u8, game: ?catalog.Game) Tree {
    const theme = controlTheme(source_theme);
    var result = Tree{ .theme = theme, .background = theme.background };
    // Receding-room fallback: the game remains the dominant subject even when
    // no compositor-owned last frame is available. A future retained texture
    // can replace this left stage without changing control geometry or focus.
    textLabel(&result, .{ .x = 48, .y = 42, .width = 520, .height = 34 }, "QUICK SYSTEM", theme.muted, uiFont(21, 28, .semibold, .start));
    if (game) |current| {
        game_object.add(&result, current, .{ .bounds = .{ .x = 72, .y = 106, .width = 300, .height = 390 }, .presentation = .cover, .dim = 42 });
        textLabel(&result, .{ .x = 48, .y = 530, .width = 500, .height = 52 }, context, theme.text, uiFont(37, 46, .semibold, .start));
        textLabel(&result, .{ .x = 48, .y = 582, .width = 500, .height = 34 }, title, theme.accent, uiFont(20, 28, .semibold, .start));
    } else {
        result.add(.{ .text_block = .{
            .bounds = .{ .x = 48, .y = 154, .width = 500, .height = 330 },
            .title = context,
            .detail = title,
            .color = theme.text,
            .detail_color = theme.accent,
            .title_font = displayFont(58, 68, .semibold, .start),
            .detail_font = uiFont(22, 30, .semibold, .start),
            .lines = 3,
            .detail_lines = 1,
            .gap = 24,
        } });
    }

    const step: u16 = if (labels.len > 5) 82 else 94;
    const top: u16 = if (labels.len > 5) 94 else 120;
    for (labels, 0..) |label, index| {
        const active = index == selected;
        const row_y = top + @as(u16, @intCast(index)) * step;
        components.editorialChoice(&result, scope, index, active, .{
            .label = label,
            .bounds = .{ .x = 632, .y = row_y, .width = 344, .height = 46 },
            .focus_bounds = .{ .x = 616, .y = row_y -| 6, .width = 376, .height = step -| 6 },
            .scale = .control,
        });
        if (values.len > index and values[index].len != 0)
            textLabel(&result, .{ .x = 632, .y = row_y + 44, .width = 344, .height = 28 }, values[index], if (active) theme.accent else theme.muted, uiFont(19, 26, if (active) .semibold else .regular, .start));
    }
    footer(&result, &.{ .{ .control = .back, .label = back_label }, .{ .control = .confirm, .label = action_label } });
    return result;
}

pub fn overlayPause(theme: Theme, game_title: []const u8, selected: usize, state_slot: usize, performance: []const u8, notice: []const u8) Tree {
    const labels = [_][]const u8{ "Continue", "Save state", "Load state", "Performance", "Save and exit" };
    const slots = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3" };
    const values = [_][]const u8{ "", slots[state_slot], "", performance, "" };
    var result = controlDeck(theme, .game_menu, "PAUSED", game_title, &labels, &values, selected, "Continue", "Select", null);
    if (notice.len != 0) showNotice(&result, notice);
    return result;
}

/// UX mock for the system-owned network route from a paused game. The actual
/// Wi-Fi picker remains the same shell surface used from Settings.
pub fn overlayPauseWithNetwork(theme: Theme, game_title: []const u8, selected: usize, state_slot: usize, performance: []const u8, network_status: []const u8, notice: []const u8) Tree {
    return overlayPauseWithNetworkGame(theme, null, game_title, selected, state_slot, performance, network_status, notice);
}

pub fn overlayPauseWithNetworkGame(theme: Theme, game: ?catalog.Game, game_title: []const u8, selected: usize, state_slot: usize, performance: []const u8, network_status: []const u8, notice: []const u8) Tree {
    const labels = [_][]const u8{ "Continue", "Save state", "Load state", "Performance", "Network", "Save and exit" };
    const slots = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3" };
    const values = [_][]const u8{ "", slots[state_slot], "", performance, network_status, "" };
    var result = controlDeck(theme, .game_menu_network, "PAUSED", game_title, &labels, &values, selected, "Continue", "Open", game);
    if (notice.len != 0) showNotice(&result, notice);
    return result;
}

pub const NetworkPrompt = enum { wifi_off, captive, limited };

/// A foreground app asks for a capability and the shell supplies the recovery
/// choices. Background traffic never opens this surface.
pub fn networkPrompt(theme: Theme, kind: NetworkPrompt, selected: usize) Tree {
    const title: []const u8 = switch (kind) {
        .wifi_off => "Connect to internet?",
        .captive => "Sign in to Wi-Fi",
        .limited => "No internet",
    };
    const subject: []const u8 = switch (kind) {
        .wifi_off => "RetroAchievements needs a connection",
        .captive => "Alder House needs you to sign in",
        .limited => "RetroAchievements could not connect",
    };
    const detail: []const u8 = switch (kind) {
        .wifi_off => "Turn on Wi-Fi and return here when connected. The game will stay paused.",
        .captive => "Open the contained sign-in page, or choose another network. The game will stay paused.",
        .limited => "Wi-Fi is connected without internet. Retry the check or choose another network.",
    };
    const off_actions = [_][]const u8{ "Not now", "Connect" };
    const captive_actions = [_][]const u8{ "Not now", "Choose network", "Sign in" };
    const limited_actions = [_][]const u8{ "Not now", "Choose network", "Retry" };
    const actions: []const []const u8 = switch (kind) {
        .wifi_off => &off_actions,
        .captive => &captive_actions,
        .limited => &limited_actions,
    };

    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, title);
    var subject_font = font.body;
    subject_font.size = 47;
    subject_font.line_height = 57;
    result.add(.{ .text_block = .{
        .bounds = .{ .x = 48, .y = 154, .width = 900, .height = 230 },
        .title = subject,
        .detail = detail,
        .color = theme.text,
        .detail_color = theme.muted,
        .title_font = subject_font,
        .detail_font = font.caption,
        .detail_lines = 2,
        .gap = 22,
    } });
    const top: u16 = if (actions.len == 2) 492 else 410;
    for (actions, 0..) |label, index| {
        var row = components.selectable(.network_prompt, index, selected == index, .{ .x = 28, .y = top + @as(u16, @intCast(index)) * 88, .width = 968, .height = 88 }, label);
        row.disclosure = false;
        row.menu(&result);
    }
    footer(&result, &.{ .{ .control = .back, .label = "Not now" }, .{ .control = .confirm, .label = "Select" } });
    return result;
}

pub fn overlayStates(theme: Theme, game_title: []const u8, selected: usize, notice: []const u8, available: [4]bool) Tree {
    return overlayStatesGame(theme, null, game_title, selected, notice, available);
}

pub fn overlayStatesGame(theme: Theme, game: ?catalog.Game, game_title: []const u8, selected: usize, notice: []const u8, available: [4]bool) Tree {
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
    const values = [_][]const u8{
        if (available[0]) details[0] else "Empty",
        if (available[1]) details[1] else "Empty",
        if (available[2]) details[2] else "Empty",
        if (available[3]) details[3] else "Empty",
    };
    result = controlDeck(theme, .overlay_states, "LOAD STATE", game_title, &labels, &values, selected, "Game menu", if (available[selected]) "Load" else "Empty", game);
    if (notice.len != 0) showNotice(&result, notice);
    return result;
}

const components = @import("ui_components.zig");
const layout = struct {
    const margin = design.spacing.margin;
    const footer_y = geometry.footer_y;
};
pub const Hint = components.Hint;
pub const Feedback = components.Feedback;
pub const FeedbackKind = components.FeedbackKind;
const textLabel = components.text;
const header = components.header;
const footer = components.footer;

fn displayFont(size: u16, line_height: u16, weight: design.Weight, alignment: design.Alignment) design.Font {
    return .{ .size = size, .line_height = line_height, .weight = weight, .family = .display, .alignment = alignment };
}

fn uiFont(size: u16, line_height: u16, weight: design.Weight, alignment: design.Alignment) design.Font {
    return .{ .size = size, .line_height = line_height, .weight = weight, .alignment = alignment };
}

fn editorialHeader(result: *Tree, section: []const u8, context: []const u8) void {
    textLabel(result, .{ .x = 48, .y = 35, .width = 300, .height = 40 }, section, result.theme.text, uiFont(25, 32, .semibold, .start));
    if (context.len != 0)
        textLabel(result, .{ .x = 540, .y = 35, .width = 436, .height = 40 }, context, result.theme.muted, uiFont(25, 32, .regular, .end));
}

fn artwork(result: *Tree, game: catalog.Game, bounds: Rect, cart: bool, selected: bool, identity: ?interaction.Id, dim: u8, tilt: i16) void {
    game_object.add(result, game, .{
        .bounds = bounds,
        .presentation = if (cart) .spatial else .cover,
        .id = identity orelse .none,
        .focused = selected,
        .dim = dim,
        .tilt = tilt,
    });
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

const foyer_view = @import("foyer_view.zig");
pub const foyer = foyer_view.foyer;
pub const foyerSession = foyer_view.session;

pub fn library(theme: Theme, games: []const catalog.Game, selected: usize, view: LibraryView, shelf_offset: i16) Tree {
    return libraryCollection(theme, .{ .games = games }, selected, selected, view, shelf_offset);
}

pub fn libraryCollection(theme: Theme, collection: catalog.Collection, selected: usize, preview_selected: usize, view: LibraryView, shelf_offset: i16) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    editorialHeader(&result, switch (view) {
        .recent => "Recent",
        .browse => "Browse",
        .all => "All games",
    }, collection.label());
    const count = collection.len();
    if (count == 0) {
        textLabel(&result, .{ .x = 48, .y = 224, .width = 928, .height = 64 }, "No games yet", theme.text, font.title);
        result.add(.{ .text = .{ .bounds = .{ .x = 48, .y = 312, .width = 864, .height = 100 }, .value = "Add games to the Roms folder on your SD card.", .color = theme.muted, .font = font.body, .lines = 2 } });
        footer(&result, &.{.{ .control = .back, .label = "Back" }});
        return result;
    }
    const game = collection.at(@min(preview_selected, count - 1));
    switch (view) {
        .recent => {
            const visible = @min(count, 5);
            const first = @min(selected -| 2, count - visible);
            for (first..first + visible) |index| {
                const entry = collection.at(index);
                const active = index == selected;
                const row_y: u16 = 126 + @as(u16, @intCast(index - first)) * 91;
                components.editorialChoice(&result, .library, index, active, .{
                    .label = entry.title,
                    .bounds = .{ .x = 48, .y = row_y, .width = 448, .height = 68 },
                    .focus_bounds = .{ .x = 48, .y = row_y, .width = 448, .height = 72 },
                    .scale = .row,
                });
            }
            artwork(&result, game, .{ .x = 566, .y = 132, .width = 382, .height = 408 }, false, true, null, 0, 0);
            textLabel(&result, .{ .x = 566, .y = 558, .width = 382, .height = 38 }, game.system, theme.muted, uiFont(24, 32, .regular, .center));
        },
        .all => {
            const visible = @min(count, 8);
            const first = @min(selected -| 3, count - visible);
            for (first..first + visible) |index| {
                const entry = collection.at(index);
                const active = index == selected;
                const row_y: u16 = 116 + @as(u16, @intCast(index - first)) * 62;
                components.editorialChoice(&result, .library, index, active, .{
                    .label = entry.title,
                    .bounds = .{ .x = 48, .y = row_y, .width = 724, .height = 52 },
                    .focus_bounds = .{ .x = 48, .y = row_y, .width = 880, .height = 52 },
                    .scale = .compact,
                });
                textLabel(&result, .{ .x = 792, .y = row_y, .width = 136, .height = 52 }, entry.system, if (active) theme.accent else theme.muted, uiFont(20, 30, if (active) .semibold else .regular, .end));
            }
            components.continuation(&result, 116, 612, first != 0, first + visible < count);
        },
        .browse => {
            const order = [_]i8{ -1, 1, 0 };
            for (order) |relative| {
                const index = @as(i64, @intCast(selected)) + relative;
                if (index < 0 or index >= count) continue;
                const pose = shelfPose(relative, shelf_offset);
                const source_index: usize = @intCast(index);
                artwork(&result, collection.at(source_index), pose.bounds, true, relative == 0, if (relative == 0) interaction.Id.scoped(.library, source_index) else null, pose.dim, pose.tilt);
                if (result.elements[result.len - 1] == .cartridge) result.elements[result.len - 1].cartridge.clip_left = pose.clip_left;
            }
            if (game.assets.card != null or game.assets.sprite != null or game.assets.preview != null)
                caption(&result, game);
        },
    }
    footer(&result, &.{ .{ .control = .menu, .label = "Device" }, .{ .control = .filter, .label = "System" }, .{ .control = .view, .label = "Density" }, .{ .control = .confirm, .label = "Play" } });
    return result;
}

const ShelfPose = struct { bounds: Rect, dim: u8, tilt: i16, clip_left: u16 };

fn shelfPose(relative: i8, offset: i16) ShelfPose {
    const position = @as(i32, relative) * 1000 + offset;
    const distance = @abs(position);
    const center = 512 + @divTrunc(position * 278, 1000);
    const width: i32 = if (distance < 1000) 300 - @as(i32, @intCast(distance * 80 / 1000)) else 220;
    const height: i32 = if (distance < 1000) 400 - @as(i32, @intCast(distance * 100 / 1000)) else 300;
    return .{
        .bounds = .{ .x = @intCast(@max(0, center - @divTrunc(width, 2))), .y = @intCast(122 + @divTrunc(400 - height, 2)), .width = @intCast(width), .height = @intCast(height) },
        .clip_left = @intCast(@max(0, @divTrunc(width, 2) - center)),
        .dim = @intCast(@min(71, distance * 71 / 1000)),
        .tilt = 0,
    };
}

pub fn gameDetail(theme: Theme, game: catalog.Game, launch_failed: ?[]const u8) Tree {
    const failed = launch_failed != null;
    var result = Tree{ .theme = theme, .background = theme.background };
    if (failed) header(&result, "Unable to start");
    artwork(&result, game, .{ .x = 48, .y = if (failed) 154 else 120, .width = 348, .height = if (failed) 392 else 430 }, false, true, null, if (failed) 28 else 0, 0);

    var title_font = font.body;
    title_font.size = 50;
    title_font.weight = .medium;
    title_font.line_height = 58;
    result.add(.{ .text_block = .{
        .bounds = .{ .x = 452, .y = 180, .width = 524, .height = 220 },
        .title = game.title,
        .detail = game.system,
        .color = theme.text,
        .detail_color = theme.muted,
        .title_font = title_font,
        .lines = 3,
        .gap = 18,
    } });
    if (failed) {
        textLabel(&result, .{ .x = 452, .y = 430, .width = 524, .height = 52 }, launch_failed.?, theme.text, uiFont(28, 40, .regular, .start));
        footer(&result, &.{ .{ .control = .back, .label = "Games" }, .{ .control = .confirm, .label = "Retry" } });
    } else {
        textLabel(&result, .{ .x = 452, .y = 454, .width = 430, .height = 42 }, "Starting", theme.muted, font.caption);
        components.activity(&result, .{ .x = 910, .y = 458, .width = 48, .height = 28 }, theme.accent);
    }
    return result;
}

const device_views = @import("device_views.zig");
pub const message = device_views.message;
pub const confirmation = device_views.confirmation;
pub const choice = device_views.choice;
pub const setting = device_views.setting;
pub const settings = device_views.settings;

const wifi_views = @import("wifi_views.zig");
pub const wifi = wifi_views.wifi;
pub const wifiFallback = wifi_views.wifiFallback;
pub const wifiPicker = wifi_views.wifiPicker;
pub const wifiNetworkDetails = wifi_views.wifiNetworkDetails;
pub const wifiPassword = wifi_views.wifiPassword;
pub const wifiHiddenName = wifi_views.wifiHiddenName;
pub const wifiConnectionInfo = wifi_views.wifiConnectionInfo;

pub fn wifiHiddenSecurity(theme: Theme, selected: usize) Tree {
    return choice(theme, "Security", &.{ "Open", "WPA2 Personal" }, selected, null, "Choose the security used by the hidden network.", "Wi-Fi");
}

pub fn bluetooth(theme: Theme, state: *const bluetooth_model.Model) Tree {
    const views = @import("bluetooth_views.zig");
    return switch (state.page) {
        .list => views.list(theme, state),
        .details => views.details(theme, state),
        .forget_confirm => confirmation(theme, "Forget device", if (state.activeDevice()) |device| device.name.slice() else "Forget this device?", "This removes its pairing and saved preferences.", "Forget", state.confirm_selected),
        .confirmation => confirmation(theme, "Pair device", if (state.snapshot.prompt_value_len == 0) "Confirm pairing?" else state.snapshot.prompt_value[0..state.snapshot.prompt_value_len], "Check that the same code appears on the other device.", "Pair", state.confirm_selected),
        .code_entry => views.code(theme, state),
        .code_display => views.displayCode(theme, state),
    };
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

pub fn showFeedback(tree: *Tree, feedback: Feedback) void {
    if (!feedback.visible()) return;
    // Keep transient feedback above the footer keyline so action hints remain
    // stable and readable while status comes and goes.
    const bounds = Rect{ .x = layout.margin, .y = geometry.feedback_y, .width = geometry.width - 2 * layout.margin, .height = geometry.feedback_height };
    components.feedbackBanner(tree, bounds, feedback);
}

pub fn showNotice(tree: *Tree, notice: []const u8) void {
    showFeedback(tree, .{ .kind = .success, .message = notice });
}

test "light and dark appearances preserve component geometry and typography" {
    const themes = @import("theme.zig");
    const light_screens = [_]Tree{ foyer(themes.light, 0), library(themes.light, &catalog.games, 0, .recent, 0), library(themes.light, &catalog.games, 0, .browse, 0), library(themes.light, &catalog.games, 0, .all, 0), settings(0, .{}, "Unavailable", "Unavailable"), overlayStates(themes.light, "Game", 0, "", @splat(false)), splash(themes.light) };
    const dark_screens = [_]Tree{ foyer(themes.dark, 0), library(themes.dark, &catalog.games, 0, .recent, 0), library(themes.dark, &catalog.games, 0, .browse, 0), library(themes.dark, &catalog.games, 0, .all, 0), settings(0, .{ .appearance = .dark }, "Unavailable", "Unavailable"), overlayStates(themes.dark, "Game", 0, "", @splat(false)), splash(themes.dark) };
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

test "windowed settings expose continuation in both directions" {
    const first = settings(0, .{}, "Off", "Off");
    var saw_down = false;
    for (first.slice()) |element| if (element == .text and std.mem.eql(u8, element.text.value, "↓")) {
        saw_down = true;
    };
    try std.testing.expect(saw_down);
    const last = settings(7, .{}, "Off", "Off");
    var saw_up = false;
    for (last.slice()) |element| if (element == .text and std.mem.eql(u8, element.text.value, "↑")) {
        saw_up = true;
    };
    try std.testing.expect(saw_up);
}

test "progress feedback owns activity while terminal feedback does not" {
    const themes = @import("theme.zig");
    var progress = Tree{ .theme = themes.light, .background = themes.light.background };
    showFeedback(&progress, .{ .kind = .progress, .message = "Connecting" });
    try std.testing.expect(progress.hasActivity());
    var success = Tree{ .theme = themes.light, .background = themes.light.background };
    showFeedback(&success, .{ .kind = .success, .message = "Connected" });
    try std.testing.expect(!success.hasActivity());
}

test "foyer reserves a stable status band above footer actions" {
    const themes = @import("theme.zig");
    var screen = foyerSession(themes.light, 0, catalog.games[0], true);
    showFeedback(&screen, .{ .kind = .success, .message = "Connected to Wi-Fi" });

    var card_bottom: u16 = 0;
    var feedback_top: ?u16 = null;
    for (screen.slice()) |element| switch (element) {
        .action_card => |card| card_bottom = @max(card_bottom, card.bounds.y + card.bounds.height),
        .bar => |bar| {
            if (bar.bounds.height == geometry.feedback_height and bar.bounds.width == geometry.width - 2 * layout.margin)
                feedback_top = bar.bounds.y;
        },
        else => {},
    };

    try std.testing.expect(feedback_top != null);
    try std.testing.expect(card_bottom <= feedback_top.?);
    try std.testing.expect(feedback_top.? + geometry.feedback_height < geometry.footer_rule_y);
}

test "settings content clears the shared status band" {
    var screen = settings(0, .{}, "Off", "Off");
    showFeedback(&screen, .{ .kind = .progress, .message = "Applying display settings" });

    var content_bottom: u16 = 0;
    for (screen.slice()) |element| switch (element) {
        .overlay_row => |row| content_bottom = @max(content_bottom, row.bounds.y + row.bounds.height),
        else => {},
    };

    try std.testing.expect(content_bottom < geometry.feedback_y);
}

test "game launch owns activity while launch failure remains terminal" {
    const themes = @import("theme.zig");
    const launching = gameDetail(themes.light, catalog.games[0], null);
    try std.testing.expect(launching.hasActivity());
    const failed = gameDetail(themes.light, catalog.games[0], "CORE UNAVAILABLE");
    try std.testing.expect(!failed.hasActivity());
}

pub fn saveSlots(theme: Theme, title: []const u8, selected: usize, available: [4]bool) Tree {
    return saveSlotsGame(theme, null, title, selected, available);
}

pub fn saveSlotsGame(theme: Theme, game: ?catalog.Game, title: []const u8, selected: usize, available: [4]bool) Tree {
    const labels = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3" };
    const values = [_][]const u8{
        if (available[0]) "Replace saved state" else "Empty",
        if (available[1]) "Replace saved state" else "Empty",
        if (available[2]) "Replace saved state" else "Empty",
    };
    return controlDeck(theme, .save_slots, "SAVE STATE", title, &labels, &values, selected, "Game menu", "Save", game);
}
