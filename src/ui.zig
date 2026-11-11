// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const design = @import("design.zig");
const font = design.typeface;
const geometry = design.geometry;
const catalog = @import("catalog.zig");
const settings_model = @import("settings.zig");
const interaction = @import("interaction.zig");
const bluetooth_model = @import("bluetooth.zig");
const scene = @import("ui_scene.zig");
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
pub const LibraryView = enum { list, shelf, grid };
pub const Cartridge = scene.Cartridge;
pub const OverlayRow = scene.OverlayRow;
pub const Element = scene.Element;
pub const Tree = scene.Tree;

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
        var row = components.selectable(.game_menu, index, index == selected, menu.overlayRow(index), label);
        row.value = if (index == 1) slots[state_slot] else if (index == 3) performance else "";
        row.disclosure = index == 2;
        row.overlay(&result);
    }
    footer(&result, &.{ .{ .control = .back, .label = "Continue" }, .{ .control = .confirm, .label = "Select" } });
    if (notice.len != 0) showNotice(&result, notice);
    return result;
}

/// UX mock for the system-owned network route from a paused game. The actual
/// Wi-Fi picker remains the same shell surface used from Settings.
pub fn overlayPauseWithNetwork(theme: Theme, game_title: []const u8, selected: usize, state_slot: usize, performance: []const u8, network_status: []const u8, notice: []const u8) Tree {
    const labels = [_][]const u8{ "Continue", "Save state", "Load state", "Performance", "Network", "Save and exit" };
    const slots = [_][]const u8{ "Slot 1", "Slot 2", "Slot 3" };
    const values = [_][]const u8{ "", slots[state_slot], "", performance, network_status, "" };
    var result = Tree{ .theme = theme, .background = theme.background };
    overlayFrame(&result, "Game menu", game_title);
    for (labels, values, 0..) |label, value, index| {
        var row = components.selectable(.game_menu_network, index, index == selected, .{ .x = 28, .y = 148 + @as(u16, @intCast(index)) * 80, .width = 968, .height = 78 }, label);
        row.value = value;
        row.disclosure = index == 2 or index == 4;
        row.overlay(&result);
    }
    footer(&result, &.{ .{ .control = .back, .label = "Continue" }, .{ .control = .confirm, .label = "Open" } });
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
    for (actions, 0..) |label, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = 28, .y = top + @as(u16, @intCast(index)) * 88, .width = 968, .height = 88 },
        .label = label,
        .selected = selected == index,
        .disclosure = false,
    } });
    footer(&result, &.{ .{ .control = .back, .label = "Not now" }, .{ .control = .confirm, .label = "Select" } });
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
            .bounds = .{ .x = 28, .y = 160 + @as(u16, @intCast(index)) * 112, .width = 968, .height = 112 },
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
const hint = components.hint;
const footer = components.footer;

fn artwork(result: *Tree, game: catalog.Game, bounds: Rect, cart: bool, selected: bool, identity: ?interaction.Id, dim: u8, tilt: i16) void {
    const sprite = if (cart) game.assets.card orelse game.assets.sprite else game.assets.cover;
    if (!cart and sprite == null and game.assets.preview == null) {
        result.add(.{ .bar = .{ .bounds = bounds, .color = if (selected) result.theme.selection else result.theme.surface, .radius = geometry.radius } });
        const inset: u16 = if (selected) 4 else 0;
        if (selected) result.add(.{ .bar = .{ .bounds = .{ .x = bounds.x + inset, .y = bounds.y + inset, .width = bounds.width - 2 * inset, .height = bounds.height - 2 * inset }, .color = result.theme.surface, .radius = geometry.radius } });
        result.add(.{ .text = .{ .bounds = .{ .x = bounds.x + 16, .y = bounds.y + bounds.height / 4, .width = bounds.width -| 32, .height = @min(120, bounds.height / 2) }, .value = game.system, .color = result.theme.muted, .font = font.caption, .lines = 2 } });
        return;
    }
    result.add(.{ .cartridge = .{
        .id = identity orelse .none,
        .state = if (identity != null) .focused else .idle,
        .bounds = bounds,
        .platform = game.platform_id,
        .texture = game.assets.preview,
        .sprite = sprite,
        .selected = selected,
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
        components.actionCard(&result, .home, 0, selected == 0, .{ .x = 28, .y = 142, .width = 614, .height = 486 }, if (resumable) "READY TO RESUME" else "LAST PLAYED", game.title, if (resumable) "Continue your last session" else "Play again", .primary, 2, 1);
        if (game.assets.cover != null or game.assets.preview != null)
            artwork(&result, game, .{ .x = 370, .y = 170, .width = 244, .height = 216 }, false, false, null, 0, 0);
        components.actionCard(&result, .home, 1, selected == 1, .{ .x = 670, .y = 142, .width = 326, .height = 229 }, "LIBRARY", "Games", "Browse your collection", .secondary, 1, 2);
        components.actionCard(&result, .home, 2, selected == 2, .{ .x = 670, .y = 399, .width = 326, .height = 229 }, "DEVICE", "Settings", "Display, audio and connections", .secondary, 1, 2);
    } else {
        components.actionCard(&result, .home, 0, selected == 0, .{ .x = 28, .y = 142, .width = 614, .height = 486 }, "LIBRARY", "Games", "Browse and play your collection", .primary, 1, 1);
        components.actionCard(&result, .home, 1, selected == 1, .{ .x = 670, .y = 142, .width = 326, .height = 486 }, "DEVICE", "Settings", "Display, audio and connections", .secondary, 1, 2);
    }
    footer(&result, &.{ .{ .control = .menu, .label = "Power" }, .{ .control = .confirm, .label = if (recent == null) "Open" else if (selected == 0) (if (resumable) "Resume" else "Play") else "Open" } });
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
                var row = components.selectable(.library, index, index == selected, .{ .x = 28, .y = 138 + @as(u16, @intCast(index - first)) * 134, .width = 968, .height = 134 }, entry.title);
                row.detail = if (collection.system == null) entry.system else "";
                row.disclosure = false;
                row.lines = if (index == selected) 2 else 1;
                row.menu(&result);
            }
        },
        .grid => {
            const first = (selected / 6) * 6;
            for (first..@min(first + 6, count)) |index| {
                const x: u16 = 48 + @as(u16, @intCast((index - first) % 3)) * 316;
                const y: u16 = 136 + @as(u16, @intCast((index - first) / 3)) * 184;
                const active = index == selected;
                components.selectable(.library, index, active, .{ .x = x, .y = y, .width = 292, .height = 172 }, "").frame(&result);
                // The grid cell owns focus; do not add a second artwork frame.
                artwork(&result, collection.at(index), .{ .x = x + 12, .y = y + 10, .width = 268, .height = 152 }, false, false, null, 0, 0);
            }
            caption(&result, game);
        },
        .shelf => {
            const order = [_]i8{ -4, 4, -3, 3, -2, 2, -1, 1, 0 };
            for (order) |relative| {
                const index = @as(i64, @intCast(selected)) + relative;
                if (index < 0 or index >= count) continue;
                const pose = shelfPose(relative, shelf_offset);
                const source_index: usize = @intCast(index);
                artwork(&result, collection.at(source_index), pose.bounds, true, relative == 0, if (relative == 0) interaction.Id.scoped(.library, source_index) else null, pose.dim, pose.tilt);
                if (result.elements[result.len - 1] == .cartridge) result.elements[result.len - 1].cartridge.clip_left = pose.clip_left;
            }
            caption(&result, game);
        },
    }
    footer(&result, &.{ .{ .control = .back, .label = "Home" }, .{ .control = .filter, .label = "System" }, .{ .control = .view, .label = "View" }, .{ .control = .confirm, .label = "Play" } });
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
    const failed = launch_failed != null;
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, if (failed) "Unable to start" else "Starting game");
    artwork(&result, game, .{ .x = 48, .y = 154, .width = 348, .height = 392 }, false, true, null, if (failed) 28 else 0, 0);

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
        result.add(.{ .bar = .{ .bounds = .{ .x = 452, .y = 438, .width = 6, .height = 84 }, .color = theme.danger } });
        result.add(.{ .text = .{ .bounds = .{ .x = 478, .y = 438, .width = 498, .height = 84 }, .value = launch_failed.?, .color = theme.text, .font = font.caption, .lines = 2 } });
        footer(&result, &.{ .{ .control = .back, .label = "Games" }, .{ .control = .confirm, .label = "Retry" } });
    } else {
        textLabel(&result, .{ .x = 452, .y = 454, .width = 430, .height = 42 }, "Preparing game", theme.muted, font.caption);
        components.activity(&result, .{ .x = 910, .y = 458, .width = 48, .height = 28 }, theme.accent);
    }
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
    for (first..first + visible) |index| {
        var row = components.selectable(.choice, index, selected == index, .{ .x = 28, .y = 138 + @as(u16, @intCast(index - first)) * step, .width = 968, .height = step }, labels[index]);
        row.value = if (active == index) "✓" else "";
        row.disclosure = false;
        row.overlay(&result);
    }
    components.continuation(&result, 138, bottom, first != 0, first + visible < labels.len);
    if (note.len != 0) result.add(.{ .text = .{ .bounds = .{ .x = 48, .y = 538, .width = 928, .height = 88 }, .value = note, .color = theme.muted, .font = font.caption, .lines = 2 } });
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
        components.meter(&result, interaction.Id.scoped(.brightness_meter, 0), .{ .x = 96, .y = 394, .width = 832, .height = 40 }, @as(u16, values.brightness) * 100);
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
        .reduced_motion => "Removes shelf animation and settles movement immediately.",
        else => "",
    };
    return choice(theme, settings_model.title(item), settings_model.labels(item), selected, active, note, "Settings");
}

pub fn settings(selected: usize, values: settings_model.Values, wifi_summary: []const u8, bluetooth_summary: []const u8) Tree {
    const theme = values.appearance.colors();
    const items = [_][]const u8{ "Brightness", "Performance", "Screen off", "Suspend", "Appearance", "Reduced motion", "Wi-Fi", "Bluetooth" };
    const details = [_][]const u8{ values.value(.brightness), values.value(.performance), values.value(.display_timeout), values.value(.suspend_timeout), values.value(.appearance), values.value(.reduced_motion), wifi_summary, bluetooth_summary };
    var result = Tree{ .theme = theme, .background = theme.background };
    header(&result, "Settings");
    const visible: usize = 5;
    const first = @min(selected -| 2, items.len - visible);
    for (items[first .. first + visible], details[first .. first + visible], first..) |item, value, index| result.add(.{ .overlay_row = .{
        .bounds = .{ .x = 28, .y = geometry.settings_top + @as(u16, @intCast(index - first)) * geometry.settings_step, .width = 968, .height = geometry.settings_height },
        .label = item,
        .detail = "",
        .value = value,
        .selected = index == selected,
        .disclosure = true,
    } });
    components.continuation(&result, geometry.settings_top, geometry.settings_top + @as(u16, @intCast(visible)) * geometry.settings_step, first != 0, first + visible < items.len);
    footer(&result, &.{ .{ .control = .back, .label = "Home" }, .{ .control = .confirm, .label = "Open" } });
    return result;
}

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
    const bounds = Rect{ .x = layout.margin, .y = layout.footer_y - 58, .width = geometry.width - 2 * layout.margin, .height = 50 };
    const marker = switch (feedback.kind) {
        .failure => tree.theme.danger,
        .warning => tree.theme.muted,
        .progress, .success => tree.theme.accent,
    };
    tree.add(.{ .bar = .{ .bounds = bounds, .color = tree.theme.surface } });
    tree.add(.{ .bar = .{ .bounds = .{ .x = bounds.x, .y = bounds.y, .width = 6, .height = bounds.height }, .color = marker } });
    const activity_width: u16 = if (feedback.kind == .progress) 58 else 0;
    textLabel(tree, .{ .x = bounds.x + 22, .y = bounds.y + 5, .width = bounds.width - 38 - activity_width, .height = 40 }, feedback.message, tree.theme.text, font.control);
    if (feedback.kind == .progress) components.activity(tree, .{ .x = bounds.x + bounds.width - 70, .y = bounds.y + 12, .width = 48, .height = 26 }, marker);
}

pub fn showNotice(tree: *Tree, notice: []const u8) void {
    showFeedback(tree, .{ .kind = .success, .message = notice });
}

test "light and dark appearances preserve component geometry and typography" {
    const themes = @import("theme.zig");
    const light_screens = [_]Tree{ home(themes.light, 0), library(themes.light, &catalog.games, 0, .list, 0), library(themes.light, &catalog.games, 0, .shelf, 0), library(themes.light, &catalog.games, 0, .grid, 0), settings(0, .{}, "Unavailable", "Unavailable"), overlayStates(themes.light, "Game", 0, "", @splat(false)), splash(themes.light) };
    const dark_screens = [_]Tree{ home(themes.dark, 0), library(themes.dark, &catalog.games, 0, .list, 0), library(themes.dark, &catalog.games, 0, .shelf, 0), library(themes.dark, &catalog.games, 0, .grid, 0), settings(0, .{ .appearance = .dark }, "Unavailable", "Unavailable"), overlayStates(themes.dark, "Game", 0, "", @splat(false)), splash(themes.dark) };
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

test "game launch owns activity while launch failure remains terminal" {
    const themes = @import("theme.zig");
    const launching = gameDetail(themes.light, catalog.games[0], null);
    try std.testing.expect(launching.hasActivity());
    const failed = gameDetail(themes.light, catalog.games[0], "CORE UNAVAILABLE");
    try std.testing.expect(!failed.hasActivity());
}

pub fn saveSlots(theme: Theme, title: []const u8, selected: usize, available: [4]bool) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    overlayFrame(&result, "Save state", title);
    for ([_][]const u8{ "Slot 1", "Slot 2", "Slot 3" }, 0..) |label, index| result.add(.{ .overlay_row = .{
        .bounds = .{ .x = 28, .y = 160 + @as(u16, @intCast(index)) * 150, .width = 968, .height = 140 },
        .label = label,
        .detail = if (available[index]) "Saved state" else "Empty",
        .selected = selected == index,
        .disclosure = false,
    } });
    footer(&result, &.{ .{ .control = .back, .label = "Game menu" }, .{ .control = .confirm, .label = "Save" } });
    return result;
}
