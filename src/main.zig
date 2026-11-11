// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const bluetooth = @import("bluetooth.zig");
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
    return snapshotTo(io, allocator, path, screen, games, selected, appearance, null);
}

fn snapshotTo(io: std.Io, allocator: std.mem.Allocator, path: []const u8, screen: []const u8, games: ?[]const catalog.Game, selected: usize, appearance: @import("theme.zig").Mode, gpu: ?*@import("gpu_renderer.zig").Display) !void {
    const pixels = try allocator.alloc(u32, render.width * render.height);
    defer allocator.free(pixels);
    @memset(pixels, 0xff13253c);
    const surface = render.Surface{ .pixels = pixels };
    var state = model.Model{};
    state.settings.appearance = appearance;
    if (std.mem.eql(u8, screen, "home") or std.mem.eql(u8, screen, "home-recent")) state.page = .home;
    if (games) |library| {
        state.games = library;
        if (library.len > 0) {
            state.selected = @min(selected, library.len - 1);
            state.game_index = state.selected;
        }
    }
    if (std.mem.eql(u8, screen, "games") or std.mem.eql(u8, screen, "games-empty") or std.mem.eql(u8, screen, "games-shelf") or std.mem.eql(u8, screen, "games-grid")) {
        state.page = .games;
        if (std.mem.eql(u8, screen, "games-empty")) state.games = &.{};
        if (std.mem.eql(u8, screen, "games-shelf")) state.library_view = .shelf;
        if (std.mem.eql(u8, screen, "games-grid")) state.library_view = .grid;
    } else if (std.mem.eql(u8, screen, "game") or std.mem.eql(u8, screen, "game-failed")) {
        state.page = .game;
        if (games == null) state.game_index = 1;
        if (std.mem.eql(u8, screen, "game-failed")) state.launch_failed = .missing_core;
    } else if (std.mem.eql(u8, screen, "settings")) {
        state.page = .settings;
    }
    if (std.mem.eql(u8, screen, "home") or std.mem.eql(u8, screen, "home-recent")) {
        state.selected = 0;
        if (games != null and state.games.len != 0) state.last_played = state.game_index;
        if (std.mem.eql(u8, screen, "home-recent")) {
            state.last_played = 1;
            state.resumable = true;
        }
    }
    if (std.mem.eql(u8, screen, "settings-overflow")) {
        state.page = .settings;
        state.selected = 7;
    }
    if (std.mem.eql(u8, screen, "settings-feedback")) {
        state.page = .settings;
        state.feedback = .{ .kind = .success, .message = "Brightness saved" };
    }
    if (std.mem.eql(u8, screen, "settings-progress")) {
        state.page = .settings;
        state.feedback = .{ .kind = .progress, .message = "Applying display settings" };
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
    var bluetooth_state = bluetooth.Model{};
    var bluetooth_snapshot = try bluetooth.parse(
        "snapshot version=1 generation=7 revision=4 radio=ready discovery=classic operation=discovery operation_device= prompt=none prompt_device= prompt_value=\n" ++
            "device id=audio0123456789abcdef0123456789ab name_hex=4c6976696e6720726f6f6d206865616470686f6e6573 kind=audio state=ready battery=82 legacy=0\n" ++
            "device id=pad00123456789abcdef0123456789ab name_hex=576972656c65737320636f6e74726f6c6c6572 kind=controller state=saved battery=64 legacy=0\n" ++
            "device id=other123456789abcdef0123456789abc name_hex=426c7565746f6f746820646576696365 kind=other state=nearby battery=-1 legacy=1\nend\n",
    );
    if (std.mem.eql(u8, screen, "bluetooth-off")) {
        bluetooth_snapshot.radio = .off;
        bluetooth_snapshot.device_count = 0;
    }
    if (std.mem.eql(u8, screen, "bluetooth-unavailable")) {
        bluetooth_snapshot.radio = .unavailable;
        bluetooth_snapshot.discovery = .idle;
        bluetooth_snapshot.operation = .none;
        bluetooth_snapshot.device_count = 0;
    }
    if (std.mem.eql(u8, screen, "bluetooth-starting")) {
        bluetooth_snapshot.radio = .starting;
        bluetooth_snapshot.discovery = .idle;
        bluetooth_snapshot.operation = .radio_change;
        bluetooth_snapshot.device_count = 0;
    }
    if (std.mem.eql(u8, screen, "bluetooth-stopping")) {
        bluetooth_snapshot.radio = .stopping;
        bluetooth_snapshot.discovery = .idle;
        bluetooth_snapshot.operation = .radio_change;
        bluetooth_snapshot.device_count = 0;
    }
    if (std.mem.eql(u8, screen, "bluetooth-connecting")) {
        bluetooth_snapshot.discovery = .idle;
        bluetooth_snapshot.operation = .connection;
        bluetooth_snapshot.operation_device = bluetooth_snapshot.devices[1].id;
    }
    if (std.mem.eql(u8, screen, "bluetooth-failed")) {
        bluetooth_snapshot.radio = .failed;
        bluetooth_snapshot.device_count = 0;
    }
    if (std.mem.eql(u8, screen, "bluetooth-pairing")) {
        bluetooth_snapshot.prompt = .confirm;
        bluetooth_snapshot.prompt_device = bluetooth_snapshot.devices[1].id;
        @memcpy(bluetooth_snapshot.prompt_value[0..6], "483921");
        bluetooth_snapshot.prompt_value_len = 6;
    }
    if (!std.mem.eql(u8, screen, "bluetooth-checking")) _ = bluetooth_state.update(bluetooth_snapshot);
    if (std.mem.eql(u8, screen, "bluetooth-details")) {
        bluetooth_state.active = bluetooth_snapshot.devices[0].id;
        bluetooth_state.page = .details;
    }
    if (std.mem.eql(u8, screen, "bluetooth-code-entry")) {
        bluetooth_state.snapshot.prompt = .pin;
        bluetooth_state.snapshot.prompt_device = bluetooth_snapshot.devices[1].id;
        bluetooth_state.active = bluetooth_snapshot.devices[1].id;
        bluetooth_state.page = .code_entry;
    }
    if (std.mem.eql(u8, screen, "bluetooth-code-display")) {
        bluetooth_state.snapshot.prompt = .display_passkey;
        @memcpy(bluetooth_state.snapshot.prompt_value[0..6], "483921");
        bluetooth_state.snapshot.prompt_value_len = 6;
        bluetooth_state.page = .code_display;
    }
    var tree = if (std.mem.startsWith(u8, screen, "bluetooth")) ui.bluetooth(state.settings.appearance.colors(), &bluetooth_state) else if (std.mem.eql(u8, screen, "wifi") or std.mem.startsWith(u8, screen, "wifi-picker") or std.mem.startsWith(u8, screen, "wifi-")) blk: {
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
        if (std.mem.eql(u8, screen, "wifi-picker-starting")) {
            wifi_snapshot.radio = .starting;
            wifi_snapshot.connectivity = .none;
            wifi_snapshot.can_scan = false;
            wifi_snapshot.network_count = 0;
        }
        if (std.mem.eql(u8, screen, "wifi-picker-stopping")) {
            wifi_snapshot.radio = .stopping;
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
        if (!std.mem.eql(u8, screen, "wifi-picker-checking")) _ = wifi_state.update(wifi_snapshot);
        if (std.mem.eql(u8, screen, "wifi-details")) break :blk ui.wifiNetworkDetails(state.settings.appearance.colors(), &wifi_state.snapshot.networks[0], 0);
        if (std.mem.eql(u8, screen, "wifi-password")) break :blk ui.wifiPassword(state.settings.appearance.colors(), "Studio", .{ .selected = 13 }, "password", false);
        if (std.mem.eql(u8, screen, "wifi-password-uppercase")) break :blk ui.wifiPassword(state.settings.appearance.colors(), "Studio", .{ .selected = 20, .uppercase = true }, "Password", true);
        if (std.mem.eql(u8, screen, "wifi-password-symbols")) break :blk ui.wifiPassword(state.settings.appearance.colors(), "Studio", .{ .selected = 22, .symbols = true }, "p@ss", true);
        if (std.mem.eql(u8, screen, "wifi-hidden-name")) break :blk ui.wifiHiddenName(state.settings.appearance.colors(), .{ .selected = 39 }, "Cafe network");
        if (std.mem.eql(u8, screen, "wifi-hidden-security")) break :blk ui.wifiHiddenSecurity(state.settings.appearance.colors(), 1);
        if (std.mem.eql(u8, screen, "wifi-info")) break :blk ui.wifiConnectionInfo(state.settings.appearance.colors(), &wifi_state.snapshot.networks[0]);
        if (std.mem.eql(u8, screen, "wifi-open-confirm")) break :blk ui.confirmation(state.settings.appearance.colors(), "Open network", "Traffic may be visible to others.", "Connect only if you trust this network.", "Connect", 0);
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
    try tree.validate();
    surface.render(&tree);
    if (gpu) |display| {
        try display.show(io, &tree);
        try display.verify(pixels);
        std.log.info("GPU oracle PASS: {s} {s}", .{ screen, @tagName(appearance) });
    } else try writePpm(io, path, pixels);
}

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    _ = arguments.next();
    var command = arguments.next() orelse {
        try snapshot(init.io, init.gpa, "brick-home.ppm", "home", null, 0, .light);
        return;
    };
    if (std.mem.eql(u8, command, "--gpu-runtime")) {
        command = arguments.next() orelse return error.MissingCommand;
    } else if (@import("builtin").cpu.arch == .aarch64 and (std.mem.eql(u8, command, "--run") or std.mem.eql(u8, command, "--run-profile") or std.mem.eql(u8, command, "--probe") or std.mem.startsWith(u8, command, "--gpu-"))) {
        return @import("gpu_runtime.zig").enter(init.minimal.args);
    }
    if (std.mem.eql(u8, command, "--gpu-check")) {
        const gpu = try @import("gpu_renderer.zig").Display.open();
        defer gpu.close();
        const suite = arguments.next();
        if (suite) |screen| if (!std.mem.eql(u8, screen, "screens") and !std.mem.eql(u8, screen, "damage")) {
            if (std.mem.eql(u8, screen, "async")) {
                const pixels = try init.gpa.alloc(u32, render.width * render.height);
                defer init.gpa.free(pixels);
                var initial = ui.settings(6, .{}, "On", "Off");
                try gpu.show(init.io, &initial);
                try @import("gpu_validation.zig").asynchronous(init.io, gpu, pixels);
                return;
            }
            try snapshotTo(init.io, init.gpa, "", screen, null, 0, .light, gpu);
            try snapshotTo(init.io, init.gpa, "", screen, null, 0, .dark, gpu);
            return;
        };
        const screens = [_][]const u8{ "splash", "home", "home-recent", "games", "games-empty", "games-shelf", "games-grid", "game", "game-failed", "settings", "settings-overflow", "settings-feedback", "settings-progress", "brightness", "performance", "display_timeout", "suspend_timeout", "appearance", "reduced_motion", "systems", "views", "power", "shutdown", "bluetooth", "bluetooth-checking", "bluetooth-off", "bluetooth-unavailable", "bluetooth-starting", "bluetooth-stopping", "bluetooth-connecting", "bluetooth-details", "bluetooth-pairing", "bluetooth-code-entry", "bluetooth-code-display", "bluetooth-failed", "wifi", "wifi-picker-checking", "wifi-picker-off", "wifi-picker-starting", "wifi-picker-stopping", "wifi-picker-error", "wifi-details", "wifi-password", "wifi-password-uppercase", "wifi-password-symbols", "wifi-hidden-name", "wifi-hidden-security", "wifi-info", "wifi-open-confirm", "wifi-forget-confirm", "overlay", "overlay-states", "overlay-network", "overlay-network-captive", "network-request-off", "network-request-captive", "network-request-limited", "languages" };
        if (suite == null or !std.mem.eql(u8, suite.?, "damage")) for ([_]@import("theme.zig").Mode{ .light, .dark }) |appearance| for (screens) |screen| {
            try snapshotTo(init.io, init.gpa, "", screen, null, 0, appearance, gpu);
        };
        if (suite != null and std.mem.eql(u8, suite.?, "screens")) return;
        const pixels = try init.gpa.alloc(u32, render.width * render.height);
        defer init.gpa.free(pixels);
        for (0..120) |i| {
            var tree = ui.settings(i % 8, .{}, "On", "Off");
            try gpu.show(init.io, &tree);
            (render.Surface{ .pixels = pixels }).render(&tree);
            try gpu.verify(pixels);
        }
        std.log.info("GPU oracle PASS: 120 aged-buffer navigation frames", .{});
        try @import("gpu_validation.zig").artwork(init.io, gpu, pixels);
        try @import("gpu_validation.zig").fineDamage(init.io, gpu, pixels);
        try @import("gpu_validation.zig").shelfDamage(init.io, gpu, pixels);
        return;
    }
    if (std.mem.eql(u8, command, "--gpu-bench")) return @import("gpu_validation.zig").benchmark(init.io, arguments.next());
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
    if (std.mem.eql(u8, command, "--run") or std.mem.eql(u8, command, "--run-profile")) {
        const profile = if (std.mem.eql(u8, command, "--run-profile")) std.meta.stringToEnum(linux_backend.Profile, arguments.next() orelse "settings") orelse return error.InvalidProfile else null;
        try linux_backend.run(init.io, profile);
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
    _ = @import("gpu_renderer.zig");
    _ = @import("frame_ownership.zig");
    _ = @import("display_scheduler.zig");
    _ = @import("gpu_scene_cache.zig");
    _ = @import("gpu_texture_cache.zig");
    _ = @import("ui_components.zig");
    _ = @import("wifi_views.zig");
    _ = @import("bluetooth_views.zig");
    _ = @import("frame_pacer.zig");
    _ = @import("input_latency.zig");
    _ = @import("interaction.zig");
    _ = @import("motion.zig");
    _ = @import("feedback.zig");
    _ = @import("focus_motion.zig");
    _ = @import("layout_motion.zig");
    _ = @import("meter_motion.zig");
    _ = @import("activity_motion.zig");
    _ = @import("navigation_motion.zig");
    _ = @import("texture_batch.zig");
    _ = @import("battery_trials.zig");
    _ = @import("bluetooth.zig");
    _ = render;
    _ = linux_backend;
    _ = model;
    _ = overlay;
    _ = @import("retroarch.zig");
    _ = scheduler;
    _ = @import("settings.zig");
    _ = @import("asset_manifest.zig");
    _ = @import("input_repeat.zig");
    _ = @import("framebuffer_pages.zig");
    _ = @import("damage.zig");
    _ = @import("damage_render_test.zig");
    _ = @import("composition.zig");
    _ = library_scan;
    _ = @import("shelf_motion.zig");
    _ = @import("library_preferences.zig");
    _ = @import("captive.zig");
    _ = @import("wifi.zig");
    _ = @import("wifi_flow.zig");
    _ = @import("wifi_ipc.zig");
    _ = @import("bluetooth_ipc.zig");
}

fn parseAppearance(value: ?[]const u8) !@import("theme.zig").Mode {
    const name = value orelse return .light;
    if (std.mem.eql(u8, name, "light")) return .light;
    if (std.mem.eql(u8, name, "dark")) return .dark;
    return error.InvalidAppearance;
}
