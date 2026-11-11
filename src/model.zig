// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const retroarch = @import("retroarch.zig");
const catalog = @import("catalog.zig");
const input = @import("input.zig");
const settings_model = @import("settings.zig");
const ui = @import("ui.zig");
const captive = @import("captive.zig");
const wifi = @import("wifi.zig");
const wifi_flow = @import("wifi_flow.zig");
const bluetooth_model = @import("bluetooth.zig");
const product_navigation = @import("product_navigation.zig");

pub const Action = input.Action;
pub const Page = product_navigation.Page;
pub const returnsToParent = product_navigation.returnsToParent;
pub const Power = enum { screen_off, suspend_device, shutdown };
const settings_count = @typeInfo(settings_model.Setting).@"enum".field_names.len;

test "direction support follows each component layout" {
    var state = Model{ .page = .games, .library_view = .browse };
    try std.testing.expect(state.supportsDirection(.left));
    try std.testing.expect(!state.supportsDirection(.up));
    state.library_view = .all;
    try std.testing.expect(state.supportsDirection(.up));
    try std.testing.expect(!state.supportsDirection(.left));
    state.page = .setting;
    state.active_setting = .brightness;
    try std.testing.expect(state.supportsDirection(.right));
    try std.testing.expect(!state.supportsDirection(.down));
    state.page = .wifi;
    state.wifi.page = .list;
    try std.testing.expect(!state.supportsDirection(.left));
    state.wifi.page = .password;
    try std.testing.expect(state.supportsDirection(.left));
}

pub const Model = struct {
    games: []const catalog.Game = &catalog.games,
    page: Page = .foyer,
    library_view: ui.LibraryView = .recent,
    system: ?usize = null,
    selected: usize = 0,
    game_index: usize = 0,
    library_selection: usize = 0,
    // Rich library content may settle after a held skim while focus and title
    // continue to track `selected` on every repeat.
    library_preview: usize = 0,
    // Source-library indices, distinct from filtered positions.
    last_played: ?usize = null,
    resumable: bool = false,
    filter_positions: [catalog.systems.len + 1]usize = @splat(0),
    feedback: ui.Feedback = .{},
    pending_launch: ?usize = null,
    launch_failed: ?retroarch.Failure = null,
    settings: settings_model.Values = .{},
    active_setting: settings_model.Setting = .brightness,
    pending_setting: ?settings_model.Setting = null,
    pending_power: ?Power = null,
    revision: u64 = 1,
    battery_percent: ?u8 = null,
    wifi: wifi_flow.Model = .{},
    wifi_fallback: captive.Snapshot = .{},
    bluetooth: bluetooth_model.Model = .{},

    pub fn collection(self: *const Model) catalog.Collection {
        return .{ .games = self.games, .system = self.system };
    }

    /// Resolve the cold-start destination after preferences and automatic-save
    /// availability are known. A valid resumable session bypasses shell
    /// navigation; otherwise the library is the root and the foyer remains only the
    /// empty/recovery foyer.
    pub fn bootTarget(self: *Model) ?usize {
        if (self.resumable) if (self.last_played) |index| if (index < self.games.len) {
            self.game_index = index;
            return index;
        };
        if (self.games.len != 0) self.browse() else {
            self.page = .foyer;
            self.selected = 0;
        }
        return null;
    }

    pub fn supportsDirection(self: *const Model, action: Action) bool {
        const vertical = action == .up or action == .down;
        const horizontal = action == .left or action == .right;
        return switch (self.page) {
            .games => switch (self.library_view) {
                .recent, .all => vertical,
                .browse => horizontal,
            },
            .setting => if (self.active_setting == .brightness) horizontal else vertical,
            .wifi => switch (self.wifi.page) {
                .list, .details => vertical,
                .password, .hidden_name, .hidden_security, .open_confirm, .forget_confirm => vertical or horizontal,
                .info => false,
            },
            .bluetooth => switch (self.bluetooth.page) {
                .list, .details => vertical,
                .forget_confirm, .confirmation, .code_entry => vertical or horizontal,
                .code_display => false,
            },
            .foyer => horizontal,
            .settings, .systems, .views, .power, .power_confirm => vertical,
            .game, .wifi_fallback => false,
        };
    }

    /// Ambient device state belongs on shell surfaces, not over play, launch,
    /// captive sign-in, or connectivity screens that already make it the task.
    pub fn showsSystemStatus(self: *const Model) bool {
        return product_navigation.chrome(self.page).ambient_status;
    }

    pub fn librarySource(self: *const Model) ?usize {
        return self.collection().sourceIndex(if (self.page == .games) self.selected else self.library_selection);
    }

    fn remember(self: *Model) void {
        if (self.page == .games) self.library_selection = self.selected;
        self.filter_positions[if (self.system) |i| i + 1 else 0] = self.library_selection;
    }

    fn browse(self: *Model) void {
        self.page = .games;
        self.selected = @min(self.library_selection, self.collection().len() -| 1);
        self.library_preview = self.selected;
    }

    pub fn settleLibraryPreview(self: *Model) bool {
        if (self.page != .games or self.library_preview == self.selected) return false;
        self.library_preview = self.selected;
        self.revision += 1;
        return true;
    }

    fn settingIndex(self: *const Model) usize {
        return switch (self.active_setting) {
            .brightness => self.settings.brightness,
            .performance => @backingInt(self.settings.performance),
            .appearance => @backingInt(self.settings.appearance),
            .display_timeout => self.settings.display_timeout,
            .suspend_timeout => self.settings.suspend_timeout,
            .reduced_motion => @intFromBool(self.settings.reduced_motion),
        };
    }

    fn chooseSetting(self: *Model) void {
        switch (self.active_setting) {
            .brightness => self.settings.brightness = @intCast(self.selected),
            .performance => self.settings.performance = @fromBackingInt(@intCast(self.selected)),
            .appearance => self.settings.appearance = @fromBackingInt(@intCast(self.selected)),
            .display_timeout => self.settings.display_timeout = @intCast(self.selected),
            .suspend_timeout => self.settings.suspend_timeout = @intCast(self.selected),
            .reduced_motion => self.settings.reduced_motion = self.selected != 0,
        }
        self.pending_setting = self.active_setting;
    }

    pub fn apply(self: *Model, action: Action) bool {
        if (self.page == .wifi_fallback) {
            if (action != .back) return false;
            self.page = .wifi;
            self.revision += 1;
            return true;
        }
        if (self.page == .wifi) {
            if (action == .back and self.wifi.page == .list) {
                self.page = .settings;
                self.selected = settings_count;
                self.wifi.wifi_state.releaseOrder();
                self.revision += 1;
                return true;
            }
            if (action == .view and self.wifi_fallback.url_len != 0 and
                self.wifi.activeNetwork() != null and
                self.wifi.activeNetwork().?.state == .sign_in)
            {
                self.page = .wifi_fallback;
                self.revision += 1;
                return true;
            }
            const changed = self.wifi.apply(action);
            if (changed) self.revision += 1;
            return changed;
        }
        if (self.page == .bluetooth) {
            if (action == .back and self.bluetooth.page == .list) {
                if (self.bluetooth.snapshot.operation != .none and self.bluetooth.snapshot.operation != .discovery) {
                    const changed = self.bluetooth.apply(action);
                    if (changed) self.revision += 1;
                    return changed;
                }
                if (self.bluetooth.snapshot.discovery != .idle)
                    _ = self.bluetooth.apply(.filter);
                self.page = .settings;
                self.selected = settings_count + 1;
                self.revision += 1;
                return true;
            }
            const changed = self.bluetooth.apply(action);
            if (changed) self.revision += 1;
            return changed;
        }
        const before_page = self.page;
        const before_selected = self.selected;
        const before_view = self.library_view;
        const before_system = self.system;
        const before_error = self.launch_failed;
        switch (action) {
            .up, .down => {
                const up = action == .up;
                if (self.page == .foyer) return false;
                if (self.page == .games and self.library_view == .browse) return false;
                if (self.page == .setting and self.active_setting == .brightness) return false;
                const step: usize = 1;
                if (up) {
                    if (step == 1 or self.selected >= step) self.selected -|= step;
                } else {
                    self.selected = @min(self.selected + step, self.itemCount() -| 1);
                }
            },
            .left, .right => {
                const left = action == .left;
                if (self.page == .foyer) {
                    self.selected = if (left) self.selected -| 1 else @min(self.selected + 1, self.itemCount() -| 1);
                } else if (self.page == .games and self.library_view == .browse) {
                    if (left) self.selected -|= 1;
                    if (!left) self.selected = @min(self.selected + 1, self.itemCount() -| 1);
                } else if (self.page == .setting and self.active_setting == .brightness) {
                    self.selected = if (left) self.selected -| 1 else @min(self.selected + 1, 10);
                    if (self.selected != before_selected) self.chooseSetting();
                }
            },
            .select => switch (self.page) {
                .foyer => {
                    const offset: usize = if (self.last_played != null) 1 else 0;
                    if (offset == 1 and self.selected == 0) {
                        self.game_index = self.last_played.?;
                        self.pending_launch = self.game_index;
                    } else if (self.selected == offset) self.browse() else {
                        self.page = .settings;
                        self.selected = 0;
                    }
                },
                .games => if (self.collection().sourceIndex(self.selected)) |index| {
                    self.remember();
                    self.game_index = index;
                    self.pending_launch = index;
                    self.launch_failed = null;
                },
                .game => {
                    if (self.launch_failed == null or self.launch_failed.?.retryable()) {
                        self.pending_launch = self.game_index;
                        self.launch_failed = null;
                    }
                },
                .settings => {
                    if (self.selected == settings_count) {
                        self.page = .wifi;
                        self.selected = 0;
                        self.wifi.page = .list;
                        self.wifi.wifi_state.releaseOrder();
                    } else if (self.selected == settings_count + 1) {
                        self.page = .bluetooth;
                        self.selected = 0;
                        self.bluetooth.page = .list;
                    } else if (self.selected == settings_count + 2) {
                        self.page = .power;
                        self.selected = 0;
                    } else {
                        self.active_setting = @fromBackingInt(@intCast(self.selected));
                        self.page = .setting;
                        self.selected = self.settingIndex();
                    }
                },
                .setting => self.chooseSetting(),
                .wifi => unreachable,
                .wifi_fallback => unreachable,
                .bluetooth => unreachable,
                .systems => {
                    self.system = if (self.selected == 0) null else self.systemAt(self.selected - 1);
                    self.library_selection = self.filter_positions[if (self.system) |i| i + 1 else 0];
                    self.browse();
                },
                .views => {
                    self.library_view = @fromBackingInt(@intCast(self.selected));
                    self.browse();
                },
                .power => if (self.selected == 2) {
                    self.page = .power_confirm;
                    self.selected = 0;
                } else {
                    self.pending_power = if (self.selected == 0) .screen_off else .suspend_device;
                },
                .power_confirm => if (self.selected == 1) {
                    self.pending_power = .shutdown;
                } else {
                    self.page = .power;
                    self.selected = 2;
                },
            },
            .back => switch (self.page) {
                .foyer => {},
                .games => {
                    self.remember();
                    // The library is the shell root. Back never detours through
                    // a dashboard before the player can choose another game.
                },
                .game => {
                    self.browse();
                    self.launch_failed = null;
                },
                .settings => {
                    self.browse();
                },
                .setting => {
                    self.page = .settings;
                    self.selected = @backingInt(self.active_setting);
                },
                .wifi => unreachable,
                .wifi_fallback => unreachable,
                .bluetooth => unreachable,
                .systems, .views => self.browse(),
                .power => {
                    self.page = .settings;
                    self.selected = settings_count + 2;
                },
                .power_confirm => {
                    self.page = .power;
                    self.selected = 2;
                },
            },
            .menu => {
                self.remember();
                self.page = product_navigation.menuDestination(self.page) orelse self.page;
                self.selected = 0;
                self.launch_failed = null;
            },
            .view => if (self.page == .games) {
                self.remember();
                self.library_view = switch (self.library_view) {
                    .recent => .browse,
                    .browse => .all,
                    .all => .recent,
                };
                self.selected = @min(self.library_selection, self.collection().len() -| 1);
                self.library_preview = self.selected;
            },
            .filter => if (self.page == .games) {
                self.remember();
                self.page = .systems;
                self.selected = 0;
            },
        }
        if (self.page == .games and before_selected != self.selected) self.library_preview = self.selected;
        const changed = before_page != self.page or before_selected != self.selected or before_view != self.library_view or before_system != self.system or before_error != self.launch_failed or self.pending_launch != null or self.pending_setting != null or self.pending_power != null;
        if (changed) self.revision += 1;
        return changed;
    }

    pub fn takeLaunch(self: *Model) ?usize {
        const pending = self.pending_launch;
        self.pending_launch = null;
        if (pending) |index| {
            if (self.collection().positionOf(index)) |position| self.library_selection = position else {
                self.system = null;
                self.library_selection = index;
            }
            self.browse();
        }
        return pending;
    }

    pub fn takeSetting(self: *Model) ?settings_model.Setting {
        const pending = self.pending_setting;
        self.pending_setting = null;
        return pending;
    }

    pub fn takeWifiRequest(self: *Model) ?wifi_flow.Request {
        return self.wifi.takeRequest();
    }

    pub fn updateWifi(self: *Model, next: wifi.Snapshot) bool {
        const previous = self.wifi.wifi_state.snapshot;
        const changed = self.wifi.update(next);
        if (changed) {
            if (previous.radio != .ready and next.radio == .ready)
                self.feedback = .{ .kind = .success, .message = "Wi-Fi on" }
            else if (previous.radio != .off and next.radio == .off)
                self.feedback = .{ .kind = .success, .message = "Wi-Fi off" }
            else {
                for (next.items()) |network| if (network.current and network.state == .connected) {
                    const was_connected = if (previous.find(network.id)) |index| previous.networks[index].state == .connected else false;
                    if (!was_connected) self.feedback = .{ .kind = .success, .message = "Connected to Wi-Fi" };
                    break;
                };
                for (previous.items()) |network| {
                    if (next.find(network.id)) |index| {
                        const current = next.networks[index];
                        if (network.state == .connected and current.state != .connected)
                            self.feedback = .{ .kind = .success, .message = "Disconnected from Wi-Fi" }
                        else if (network.auto_connect != current.auto_connect)
                            self.feedback = .{ .kind = .success, .message = if (current.auto_connect) "Auto-connect on" else "Auto-connect off" }
                        else if (network.private_address != current.private_address)
                            self.feedback = .{ .kind = .success, .message = if (current.private_address) "Private address on" else "Private address off" };
                    } else if (network.saved) {
                        self.feedback = .{ .kind = .success, .message = "Network forgotten" };
                    }
                }
            }
        }
        if (changed) self.revision += 1;
        return changed;
    }

    pub fn takeBluetoothCommand(self: *Model) ?bluetooth_model.Command {
        return self.bluetooth.takeCommand();
    }

    pub fn updateBluetooth(self: *Model, next: bluetooth_model.Snapshot) bool {
        const previous = self.bluetooth.snapshot;
        const changed = self.bluetooth.update(next);
        if (changed) {
            if (previous.radio != .ready and next.radio == .ready)
                self.feedback = .{ .kind = .success, .message = "Bluetooth on" }
            else if (previous.radio != .off and next.radio == .off)
                self.feedback = .{ .kind = .success, .message = "Bluetooth off" }
            else if (previous.operation != .none and next.operation == .none) self.feedback = switch (previous.operation) {
                .pairing => .{ .kind = .success, .message = "Device paired" },
                .connection => .{ .kind = .success, .message = "Device connected" },
                .disconnection => .{ .kind = .success, .message = "Device disconnected" },
                .forget => .{ .kind = .success, .message = "Device forgotten" },
                .radio_change, .discovery, .none => self.feedback,
            } else if (previous.discovery != .idle and next.discovery == .idle)
                self.feedback = .{ .kind = .success, .message = "Device search finished" }
            else {
                for (previous.items()) |device| {
                    if (next.find(device.id)) |index| {
                        const current = next.devices[index];
                        const was_connected = device.state == .connected or device.state == .preparing_audio or device.state == .ready;
                        const is_connected = current.state == .connected or current.state == .preparing_audio or current.state == .ready;
                        if (!was_connected and is_connected)
                            self.feedback = .{ .kind = .success, .message = "Device connected" }
                        else if ((device.state == .connected or device.state == .preparing_audio) and current.state == .ready)
                            self.feedback = .{ .kind = .success, .message = "Game audio ready" }
                        else if (was_connected and !is_connected)
                            self.feedback = .{ .kind = .success, .message = "Device disconnected" };
                    } else if (device.state != .nearby) {
                        self.feedback = .{ .kind = .success, .message = "Device forgotten" };
                    }
                }
            }
        }
        if (changed) self.revision += 1;
        return changed;
    }

    pub fn launchFailed(self: *Model, failure: retroarch.Failure) void {
        self.launch_failed = failure;
        self.page = .game;
        self.revision += 1;
    }

    pub fn hasSystem(self: *const Model, index: usize) bool {
        return (catalog.Collection{ .games = self.games, .system = index }).len() > 0;
    }

    pub fn systemAt(self: *const Model, position: usize) ?usize {
        var n: usize = 0;
        for (catalog.systems, 0..) |_, i| {
            if (!self.hasSystem(i)) continue;
            if (n == position) return i;
            n += 1;
        }
        return null;
    }

    fn itemCount(self: *const Model) usize {
        return switch (self.page) {
            .foyer => if (self.last_played != null) 3 else 2,
            .games => self.collection().len(),
            .game => 1,
            .settings => settings_count + 3,
            .setting => settings_model.labels(self.active_setting).len,
            .wifi => 1,
            .wifi_fallback => 1,
            .bluetooth => 1,
            .views, .power => 3,
            .power_confirm => 2,
            .systems => blk: {
                var count: usize = 1;
                for (catalog.systems, 0..) |_, i| if (self.hasSystem(i)) {
                    count += 1;
                };
                break :blk count;
            },
        };
    }

    pub fn tree(self: *const Model) ui.Tree {
        return self.treeWithShelfOffset(0);
    }

    pub fn treeWithShelfOffset(self: *const Model, shelf_offset: i16) ui.Tree {
        const theme = self.settings.appearance.colors();
        var result = switch (self.page) {
            .foyer => ui.foyerSession(theme, self.selected, if (self.last_played) |index| self.games[index] else null, self.resumable),
            .games => ui.libraryCollection(theme, self.collection(), self.selected, self.library_preview, self.library_view, shelf_offset),
            .game => if (self.games.len == 0) ui.library(theme, self.games, 0, self.library_view, 0) else ui.gameDetail(theme, self.games[self.game_index], self.launch_failed),
            .settings => ui.settings(self.selected, self.settings, self.wifi.wifi_state.summary(), self.bluetooth.summary()),
            .setting => ui.setting(self.active_setting, self.selected, self.settingIndex(), self.settings),
            .wifi => self.wifiTree(theme),
            .wifi_fallback => ui.wifiFallback(theme, self.wifi_fallback.url(), &self.wifi_fallback.qr),
            .bluetooth => ui.bluetooth(theme, &self.bluetooth),
            .views => ui.choice(theme, "Library density", &.{ "Recent", "Browse", "All games" }, self.selected, @backingInt(self.library_view), "One collection, tuned for returning, exploring, or locating precisely.", "Library"),
            .systems => blk: {
                var labels: [catalog.systems.len + 1][]const u8 = undefined;
                labels[0] = "All systems";
                var count: usize = 1;
                var active: usize = 0;
                for (catalog.systems, 0..) |system, i| if (self.hasSystem(i)) {
                    labels[count] = system.label;
                    if (self.system == i) active = count;
                    count += 1;
                };
                break :blk ui.choice(theme, "System", labels[0..count], self.selected, active, "", "Games");
            },
            .power => ui.choice(theme, "Power", &.{ "Turn screen off", "Sleep", "Shut down" }, self.selected, null, "Sleep disconnects Bluetooth devices.", "Settings"),
            .power_confirm => ui.confirmation(theme, "Shut down", "Turn off the device?", "Hold Power to start it again.", "Shut down", self.selected),
        };
        if (self.showsSystemStatus()) {
            const network: ui.NetworkStatus = if (self.wifi.wifi_state.initialized) switch (self.wifi.wifi_state.snapshot.connectivity) {
                .internet => .connected,
                .local, .captive, .limited => .attention,
                .none => .hidden,
            } else .hidden;
            ui.systemStatus(&result, .{ .battery = self.battery_percent, .network = network });
        }
        // Direct manipulation and connectivity settle in place. Routine
        // success is represented by the changed value, row, or system-status
        // icon; only work in flight or an outcome needing attention interrupts
        // the composition with prose.
        if (self.feedback.visible() and self.feedback.kind != .success) ui.showFeedback(&result, self.feedback);
        return result;
    }

    fn wifiTree(self: *const Model, theme: @import("theme.zig").Theme) ui.Tree {
        const flow = &self.wifi;
        return switch (flow.page) {
            .list => ui.wifiPicker(theme, &flow.wifi_state),
            .details => if (flow.activeNetwork()) |network|
                ui.wifiNetworkDetails(theme, network, flow.detail_selected)
            else
                ui.wifiPicker(theme, &flow.wifi_state),
            .password => ui.wifiPassword(theme, if (flow.activeNetwork()) |network| network.name.slice() else "Hidden network", .{ .selected = flow.field.selected, .uppercase = flow.field.uppercase, .symbols = flow.field.symbols }, flow.field.slice(), flow.show_password),
            .hidden_name => ui.wifiHiddenName(theme, .{ .selected = flow.field.selected, .uppercase = flow.field.uppercase, .symbols = flow.field.symbols }, flow.field.slice()),
            .hidden_security => ui.wifiHiddenSecurity(theme, @backingInt(flow.hidden_security)),
            .info => if (flow.activeNetwork()) |network|
                ui.wifiConnectionInfo(theme, network)
            else
                ui.wifiPicker(theme, &flow.wifi_state),
            .open_confirm => ui.confirmation(theme, "Open network", "Traffic may be visible to others.", "Connect only if you trust this network.", "Connect", flow.confirm_selected),
            .forget_confirm => ui.confirmation(theme, "Forget network", if (flow.activeNetwork()) |network| network.name.slice() else "Forget this network?", "This removes its password, private address and sign-in data.", "Forget", flow.confirm_selected),
        };
    }
};

test "foyer opens Games and returns without losing browsing position" {
    var state = Model{};
    try std.testing.expectEqual(Page.foyer, state.page);
    _ = state.apply(.select);
    _ = state.apply(.down);
    _ = state.apply(.back);
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.games, state.page);
    try std.testing.expectEqual(@as(usize, 1), state.selected);
}

test "boot resumes valid play and otherwise enters the library" {
    var state = Model{ .last_played = 2, .resumable = true };
    try std.testing.expectEqual(@as(?usize, 2), state.bootTarget());
    state = .{ .last_played = 2, .resumable = false };
    try std.testing.expect(state.bootTarget() == null);
    try std.testing.expectEqual(Page.games, state.page);
    state = .{ .games = &.{} };
    try std.testing.expect(state.bootTarget() == null);
    try std.testing.expectEqual(Page.foyer, state.page);
}

test "filtered launch uses source identity and restores each system position" {
    var state = Model{ .page = .games, .selected = 4 };
    _ = state.apply(.filter);
    // All, NES, Game Boy, Game Boy Advance, Mega Drive.
    _ = state.apply(.down);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqualStrings("Game Boy", state.collection().label());
    _ = state.apply(.select);
    try std.testing.expectEqual(@as(?usize, 2), state.takeLaunch());
    _ = state.apply(.filter);
    _ = state.apply(.select);
    try std.testing.expectEqual(@as(usize, 4), state.selected);
}

test "density control changes the collection in place and retains selection" {
    var state = Model{ .page = .games, .selected = 2 };
    _ = state.apply(.view);
    try std.testing.expectEqual(ui.LibraryView.browse, state.library_view);
    try std.testing.expectEqual(Page.games, state.page);
    _ = state.apply(.view);
    try std.testing.expectEqual(ui.LibraryView.all, state.library_view);
    try std.testing.expectEqual(@as(usize, 2), state.selected);
    try std.testing.expect(!state.apply(.right));
    _ = state.apply(.down);
    try std.testing.expectEqual(@as(usize, 3), state.selected);
    _ = state.apply(.down);
    try std.testing.expectEqual(@as(usize, 4), state.selected);
    try std.testing.expect(!state.apply(.down));
}

test "library is the root and device controls are intentional" {
    var state = Model{ .page = .games, .selected = 2 };
    try std.testing.expect(!state.apply(.back));
    try std.testing.expectEqual(Page.games, state.page);
    _ = state.apply(.menu);
    try std.testing.expectEqual(Page.settings, state.page);
    _ = state.apply(.back);
    try std.testing.expectEqual(Page.games, state.page);
}

test "Menu reveals and dismisses the system instead of cycling destinations" {
    var state = Model{ .page = .games, .selected = 2 };
    _ = state.apply(.menu);
    try std.testing.expectEqual(Page.settings, state.page);
    _ = state.apply(.menu);
    try std.testing.expectEqual(Page.games, state.page);
}

test "library preview can trail a skim and settle on release" {
    var state = Model{ .page = .games, .selected = 3, .library_preview = 1 };
    try std.testing.expect(state.settleLibraryPreview());
    try std.testing.expectEqual(@as(usize, 3), state.library_preview);
    try std.testing.expect(!state.settleLibraryPreview());
}

test "empty collections and absent history cannot launch" {
    var state = Model{ .page = .games, .games = &.{} };
    for ([_]Action{ .down, .right, .select, .up, .back, .select }) |action| _ = state.apply(action);
    try std.testing.expect(state.takeLaunch() == null);
    _ = state.tree();
}

test "settings choices commit explicitly and brightness clamps" {
    var state = Model{ .page = .settings, .selected = 4 };
    _ = state.apply(.select);
    _ = state.apply(.down);
    try std.testing.expect(state.takeSetting() == null);
    _ = state.apply(.select);
    try std.testing.expectEqual(settings_model.Setting.appearance, state.takeSetting().?);
    try std.testing.expectEqual(@import("theme.zig").Mode.dark, state.settings.appearance);
    state.active_setting = .brightness;
    state.selected = 10;
    try std.testing.expect(!state.apply(.right));
    _ = state.apply(.left);
    try std.testing.expectEqual(@as(u8, 9), state.settings.brightness);
}

test "history launch leaves a different filter without changing save identity" {
    var state = Model{ .last_played = 4, .system = 1 };
    _ = state.apply(.select);
    try std.testing.expectEqual(@as(?usize, 4), state.takeLaunch());
    try std.testing.expect(state.system == null);
    try std.testing.expectEqual(@as(usize, 4), state.selected);
    state.launchFailed(.emulator);
    _ = state.apply(.select);
    try std.testing.expectEqual(@as(?usize, 4), state.takeLaunch());
    state.launchFailed(.missing_core);
    try std.testing.expect(!state.apply(.select));
    try std.testing.expect(state.takeLaunch() == null);
}

test "shutdown requires an explicit confirmation and cancel is default" {
    var state = Model{ .page = .power, .selected = 2 };
    _ = state.apply(.select);
    try std.testing.expect(state.pending_power == null);
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.power, state.page);
    _ = state.apply(.select);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(Power.shutdown, state.pending_power.?);
}

test "Power is an explicit Device destination and Back restores its row" {
    var state = Model{ .page = .settings, .selected = settings_count + 2 };
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.power, state.page);
    _ = state.apply(.back);
    try std.testing.expectEqual(Page.settings, state.page);
    try std.testing.expectEqual(settings_count + 2, state.selected);
}

test "Back at the foyer is inert with or without a resumable session" {
    inline for (.{ false, true }) |history| {
        var state = Model{ .last_played = if (history) 1 else null, .resumable = history, .library_selection = 3 };
        const revision = state.revision;
        for (0..8) |_| try std.testing.expect(!state.apply(.back));
        try std.testing.expectEqual(Page.foyer, state.page);
        try std.testing.expectEqual(@as(usize, 0), state.selected);
        try std.testing.expectEqual(revision, state.revision);
        try std.testing.expect(state.takeLaunch() == null);
        try std.testing.expect(state.pending_power == null);
    }
}

test "settings list never changes values through unadvertised shortcuts" {
    var state = Model{ .page = .settings, .selected = 0 };
    const before = state.settings;
    for (0..20) |_| _ = state.apply(.right);
    try std.testing.expectEqual(@as(u8, 10), state.settings.brightness);
    for (0..20) |_| _ = state.apply(.left);
    try std.testing.expectEqualDeep(before, state.settings);
    try std.testing.expectEqual(@as(?settings_model.Setting, null), state.takeSetting());
}

test "Wi-Fi picker commands retain the authority generation" {
    var state = Model{ .page = .settings, .selected = settings_count };
    _ = state.updateWifi(try wifi.parse(
        "snapshot generation=19 revision=2 radio=ready connectivity=captive can_scan=1\n" ++
            "network id=home name_hex=486f6d65 security=wpa2_personal signal=strong state=sign_in saved=1 current=1 in_range=1 auto=1 private=1 address_hex=\n" ++
            "end\n",
    ));
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.wifi, state.page);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(wifi_flow.Page.details, state.wifi.page);
    _ = state.apply(.select);
    const request = state.takeWifiRequest().?;
    try std.testing.expectEqual(wifi.CommandKind.open_captive, request.command.kind);
    try std.testing.expectEqual(@as(u32, 19), request.command.generation);
}

test "Wi-Fi settings row ignores setting adjustment shortcuts" {
    var state = Model{ .page = .settings, .selected = settings_count };
    const before = state.settings;
    try std.testing.expect(!state.apply(.left));
    try std.testing.expect(!state.apply(.right));
    try std.testing.expectEqualDeep(before, state.settings);
    try std.testing.expectEqual(@as(?settings_model.Setting, null), state.takeSetting());
}

test "Wi-Fi input tree preserves the active keyboard character set" {
    var state = Model{ .page = .wifi };
    state.wifi.page = .password;
    state.wifi.field.selected = 22;
    state.wifi.field.uppercase = true;
    state.wifi.field.symbols = true;
    const tree = state.tree();
    for (tree.slice()) |element| if (element == .keyboard) {
        try std.testing.expectEqual(@as(u8, 22), element.keyboard.selected);
        try std.testing.expect(element.keyboard.uppercase);
        try std.testing.expect(element.keyboard.symbols);
        return;
    };
    return error.MissingKeyboard;
}

test "radio and device snapshot transitions produce positive feedback" {
    var state = Model{};
    _ = state.updateBluetooth(try bluetooth_model.parse("snapshot version=1 generation=1 revision=1 radio=starting discovery=idle operation=radio_change operation_device= prompt=none prompt_device= prompt_value=\nend\n"));
    _ = state.updateBluetooth(try bluetooth_model.parse("snapshot version=1 generation=1 revision=2 radio=ready discovery=idle operation=none operation_device= prompt=none prompt_device= prompt_value=\nend\n"));
    try std.testing.expectEqual(ui.FeedbackKind.success, state.feedback.kind);
    try std.testing.expectEqualStrings("Bluetooth on", state.feedback.message);

    _ = state.updateWifi(try wifi.parse("snapshot generation=2 revision=1 radio=starting connectivity=none can_scan=0\nend\n"));
    _ = state.updateWifi(try wifi.parse("snapshot generation=2 revision=2 radio=ready connectivity=internet can_scan=1\nend\n"));
    try std.testing.expectEqual(ui.FeedbackKind.success, state.feedback.kind);
    try std.testing.expectEqualStrings("Wi-Fi on", state.feedback.message);

    _ = state.updateBluetooth(try bluetooth_model.parse(
        "snapshot version=1 generation=3 revision=1 radio=ready discovery=idle operation=none operation_device= prompt=none prompt_device= prompt_value=\n" ++
            "device id=headphones name_hex=4865616470686f6e6573 kind=audio state=connected battery=80 legacy=0\nend\n",
    ));
    _ = state.updateBluetooth(try bluetooth_model.parse(
        "snapshot version=1 generation=3 revision=2 radio=ready discovery=idle operation=none operation_device= prompt=none prompt_device= prompt_value=\n" ++
            "device id=headphones name_hex=4865616470686f6e6573 kind=audio state=ready battery=80 legacy=0\nend\n",
    ));
    try std.testing.expectEqual(ui.FeedbackKind.success, state.feedback.kind);
    try std.testing.expectEqualStrings("Game audio ready", state.feedback.message);
}

test "routine connection success settles into the foyer status cluster" {
    var state = Model{ .page = .foyer, .last_played = 0, .resumable = true, .battery_percent = 72 };
    state.wifi.wifi_state.initialized = true;
    state.wifi.wifi_state.snapshot.radio = .ready;
    state.wifi.wifi_state.snapshot.connectivity = .internet;
    state.feedback = .{ .kind = .success, .message = "Connected to Wi-Fi" };
    const tree = state.tree();

    var signal_bars: usize = 0;
    var success_copy = false;
    for (tree.slice()) |element| switch (element) {
        .bar => |bar| if (bar.bounds.x >= 872 and bar.bounds.x < 900) {
            signal_bars += 1;
        },
        .text => |value| success_copy = success_copy or std.mem.eql(u8, value.value, "Connected to Wi-Fi"),
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 4), signal_bars);
    try std.testing.expect(!success_copy);
}

test "captive network exposes bounded manual fallback and returns to Wi-Fi" {
    var state = Model{ .page = .wifi };
    _ = state.updateWifi(try wifi.parse(
        "snapshot generation=7 revision=2 radio=ready connectivity=captive can_scan=1\n" ++
            "network id=portal name_hex=506f7274616c security=open signal=good state=sign_in saved=1 current=1 in_range=1 auto=1 private=1 address_hex=3139322e302e322e32\n" ++
            "end\n",
    ));
    state.wifi.wifi_state.selected = 1;
    _ = state.apply(.select);
    state.wifi_fallback = captive.parse("generation=7\nux_state=sign-in-required\nportal_url=http://portal.test/\n");
    try std.testing.expect(state.apply(.view));
    try std.testing.expectEqual(Page.wifi_fallback, state.page);
    try std.testing.expectEqualStrings("http://portal.test/", state.wifi_fallback.url());
    try std.testing.expect(state.apply(.back));
    try std.testing.expectEqual(Page.wifi, state.page);
}
