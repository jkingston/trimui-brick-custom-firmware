// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const catalog = @import("catalog.zig");
const linux_backend = @import("linux_backend.zig");
const library_scan = @import("library_scan.zig");
const model = @import("model.zig");
const overlay = @import("overlay.zig");
const render = @import("render.zig");
const scheduler = @import("scheduler.zig");
const ui = @import("ui.zig");

pub fn writePpm(io: std.Io, path: []const u8, pixels: []const u32) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var output_buffer: [16 * 1024]u8 = undefined;
    var writer = file.writer(io, &output_buffer);
    var header: [64]u8 = undefined;
    const text = try std.fmt.bufPrint(&header, "P6\n{d} {d}\n255\n", .{ render.width, render.height });
    try writer.interface.writeAll(text);
    var row: [render.width * 3]u8 = undefined;
    var y: usize = 0;
    while (y < render.height) : (y += 1) {
        for (pixels[y * render.width .. (y + 1) * render.width], 0..) |pixel, x| {
            row[x * 3] = @truncate(pixel >> 16);
            row[x * 3 + 1] = @truncate(pixel >> 8);
            row[x * 3 + 2] = @truncate(pixel);
        }
        try writer.interface.writeAll(&row);
    }
    try writer.interface.flush();
}

fn snapshot(io: std.Io, allocator: std.mem.Allocator, path: []const u8, screen: []const u8, games: ?[]const catalog.Game, selected: usize, appearance: @import("theme.zig").Mode) !void {
    const pixels = try allocator.alloc(u32, render.width * render.height);
    defer allocator.free(pixels);
    @memset(pixels, 0xff13253c);
    const surface = render.Surface{ .pixels = pixels };
    var state = model.Model{};
    state.settings.appearance = appearance;
    if (std.mem.eql(u8, screen, "home")) state.page = .home;
    if (games) |library| {
        state.games = library;
        if (library.len > 0) {
            state.selected = @min(selected, library.len - 1);
            state.game_index = state.selected;
        }
    }
    if (std.mem.eql(u8, screen, "games") or std.mem.eql(u8, screen, "games-shelf") or std.mem.eql(u8, screen, "games-grid")) {
        state.page = .games;
        if (std.mem.eql(u8, screen, "games-shelf")) state.library_view = .shelf;
        if (std.mem.eql(u8, screen, "games-grid")) state.library_view = .grid;
    } else if (std.mem.eql(u8, screen, "game")) {
        state.page = .game;
        if (games == null) state.game_index = 1;
    } else if (std.mem.eql(u8, screen, "settings")) {
        state.page = .settings;
    }
    if (std.mem.eql(u8, screen, "home")) {
        state.selected = 0;
        if (games != null and state.games.len != 0) state.last_played = state.game_index;
    }
    if (std.mem.eql(u8, screen, "systems")) {
        state.page = .systems;
        state.selected = 0;
    }
    if (std.mem.eql(u8, screen, "views")) {
        state.page = .views;
        state.selected = 0;
    }
    if (std.mem.eql(u8, screen, "power")) {
        state.page = .power;
        state.selected = 0;
    }
    if (std.mem.eql(u8, screen, "shutdown")) {
        state.page = .power_confirm;
        state.selected = 0;
    }
    inline for (@typeInfo(@import("settings.zig").Setting).@"enum".field_names, 0..) |name, index| {
        if (std.mem.eql(u8, screen, name)) {
            state.page = .setting;
            state.active_setting = @fromBackingInt(index);
            state.selected = 0;
        }
    }
    var tree = if (std.mem.eql(u8, screen, "wifi") or std.mem.startsWith(u8, screen, "wifi-picker") or std.mem.startsWith(u8, screen, "wifi-")) blk: {
        const wifi = @import("wifi.zig");
        var wifi_state = wifi.Model{};
        var wifi_snapshot = try wifi.parse(
            "snapshot generation=4 revision=12 radio=ready connectivity=captive can_scan=1\n" ++
                "network id=alder-secure name_hex=416c64657220486f757365 address_hex=3139322e3136382e312e3233 security=wpa2_personal signal=strong state=sign_in saved=1 current=1 in_range=1 auto=1 private=1\n" ++
                "network id=studio name_hex=53747564696f security=wpa2_personal signal=good state=saved saved=1 current=0 in_range=1 auto=1 private=1\n" ++
                "network id=train-open name_hex=547261696e2057694669 security=open signal=fair state=available saved=0 current=0 in_range=1 auto=0 private=1\n" ++
                "end\n",
        );
        if (std.mem.eql(u8, screen, "wifi-picker-off")) {
            wifi_snapshot.radio = .off;
            wifi_snapshot.connectivity = .none;
            wifi_snapshot.can_scan = false;
            wifi_snapshot.network_count = 0;
        }
        if (std.mem.eql(u8, screen, "wifi-picker-error")) {
            wifi_snapshot.radio = .failed;
            wifi_snapshot.connectivity = .none;
            wifi_snapshot.can_scan = false;
            wifi_snapshot.network_count = 0;
        }
        _ = wifi_state.update(wifi_snapshot);
        if (std.mem.eql(u8, screen, "wifi-details")) break :blk ui.wifiNetworkDetails(state.settings.appearance.colors(), &wifi_state.snapshot.networks[0], 0);
        if (std.mem.eql(u8, screen, "wifi-password")) break :blk ui.wifiPassword(state.settings.appearance.colors(), "Studio", 13, "password", false);
        if (std.mem.eql(u8, screen, "wifi-hidden-name")) break :blk ui.wifiHiddenName(state.settings.appearance.colors(), 39, "Cafe network");
        if (std.mem.eql(u8, screen, "wifi-hidden-security")) break :blk ui.wifiHiddenSecurity(state.settings.appearance.colors(), 1);
        if (std.mem.eql(u8, screen, "wifi-info")) break :blk ui.wifiConnectionInfo(state.settings.appearance.colors(), &wifi_state.snapshot.networks[0]);
        if (std.mem.eql(u8, screen, "wifi-open-confirm")) break :blk ui.confirmation(state.settings.appearance.colors(), "Open network", "Traffic may be visible to others.", "Connect only if you trust this network.", "Connect", 1);
        if (std.mem.eql(u8, screen, "wifi-forget-confirm")) break :blk ui.confirmation(state.settings.appearance.colors(), "Forget network", "Forget Alder House?", "This disconnects and removes its password and private address.", "Forget", 0);
        break :blk ui.wifiPicker(state.settings.appearance.colors(), &wifi_state);
    } else if (std.mem.eql(u8, screen, "splash")) ui.splash(state.settings.appearance.colors()) else if (std.mem.eql(u8, screen, "languages")) ui.languageProof(state.settings.appearance.colors()) else if (std.mem.eql(u8, screen, "overlay-network")) ui.overlayPauseWithNetwork(state.settings.appearance.colors(), "Advance Wars", 4, 0, "Balanced", "Connected", "") else if (std.mem.eql(u8, screen, "overlay-network-captive")) ui.overlayPauseWithNetwork(state.settings.appearance.colors(), "Advance Wars", 4, 0, "Balanced", "Sign-in required", "") else if (std.mem.eql(u8, screen, "network-request-off")) ui.networkPrompt(state.settings.appearance.colors(), .wifi_off, 1) else if (std.mem.eql(u8, screen, "network-request-captive")) ui.networkPrompt(state.settings.appearance.colors(), .captive, 2) else if (std.mem.eql(u8, screen, "network-request-limited")) ui.networkPrompt(state.settings.appearance.colors(), .limited, 2) else if (std.mem.startsWith(u8, screen, "overlay")) blk: {
        var game_overlay = overlay.Model{ .appearance = appearance, .title = if (state.games.len != 0) state.games[state.game_index].title else "Game" };
        inline for (@typeInfo(overlay.Layer).@"enum".field_names, 0..) |name, index| {
            if (std.mem.eql(u8, screen, "overlay-" ++ name)) game_overlay.layer = @fromBackingInt(index);
        }
        if (std.mem.eql(u8, screen, "overlay-states")) game_overlay.available = .{ true, false, false, true };
        if (game_overlay.layer == .failure) game_overlay.notice = "The state could not be saved. The game is still open.";
        break :blk game_overlay.tree();
    } else state.tree();
    surface.render(&tree);
    try writePpm(io, path, pixels);
}

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    _ = arguments.next();
    const command = arguments.next() orelse {
        try snapshot(init.io, init.gpa, "brick-home.ppm", "home", null, 0, .light);
        return;
    };
    if (std.mem.eql(u8, command, "--snapshot")) {
        const path = arguments.next() orelse return error.MissingPath;
        const screen = arguments.next() orelse "home";
        try snapshot(init.io, init.gpa, path, screen, null, 0, try parseAppearance(arguments.next()));
        return;
    }
    if (std.mem.eql(u8, command, "--snapshot-library")) {
        const path = arguments.next() orelse return error.MissingPath;
        const screen = arguments.next() orelse "games";
        const root = arguments.next() orelse "/data";
        const selected = if (arguments.next()) |value| try std.fmt.parseInt(usize, value, 10) else 0;
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        defer arena.deinit();
        const library = try catalog.discover(init.io, arena.allocator(), root);
        try snapshot(init.io, arena.allocator(), path, screen, library, selected, try parseAppearance(arguments.next()));
        return;
    }
    if (std.mem.eql(u8, command, "--idle-proof")) {
        var plan = scheduler.Scheduler{};
        plan.rendered(0);
        if (plan.nextWake(1) != null) return error.UnexpectedWakeup;
        return;
    }
    if (std.mem.eql(u8, command, "--run")) {
        try linux_backend.run(init.io);
        return;
    }
    if (std.mem.eql(u8, command, "--probe")) {
        try linux_backend.probe(init.io);
        return;
    }
    if (std.mem.eql(u8, command, "--scan-library")) {
        const root = arguments.next() orelse "/data";
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        defer arena.deinit();
        try library_scan.write(init.io, arena.allocator(), root);
        return;
    }
    return error.UnknownCommand;
}

test {
    _ = render;
    _ = linux_backend;
    _ = model;
    _ = overlay;
    _ = @import("retroarch.zig");
    _ = scheduler;
    _ = @import("settings.zig");
    _ = @import("asset_manifest.zig");
    _ = @import("input_repeat.zig");
    _ = library_scan;
    _ = @import("shelf_motion.zig");
    _ = @import("library_preferences.zig");
    _ = @import("captive.zig");
    _ = @import("wifi.zig");
    _ = @import("wifi_flow.zig");
    _ = @import("wifi_ipc.zig");
}

fn parseAppearance(value: ?[]const u8) !@import("theme.zig").Mode {
    const name = value orelse return .light;
    if (std.mem.eql(u8, name, "light")) return .light;
    if (std.mem.eql(u8, name, "dark")) return .dark;
    return error.InvalidAppearance;
}
