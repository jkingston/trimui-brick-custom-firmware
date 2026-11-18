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
pub const ArtworkCommand = enum { refresh_game, set_title, import_local, remove_game, reset_game, refresh_missing, remove_all };
pub const ArtworkRequest = struct {
    command: ArtworkCommand,
    game: ?usize = null,
    value: [96]u8 = @splat(0),
    value_len: u8 = 0,

    pub fn valueSlice(self: *const ArtworkRequest) []const u8 {
        return self.value[0..self.value_len];
    }
};
const settings_count = @typeInfo(settings_model.Setting).@"enum".field_names.len;
pub const maximum_history = 16;

test "direction support follows each component layout" {
    var state = Model{ .page = .games, .library_view = .recent };
    try std.testing.expect(state.supportsDirection(.up));
    try std.testing.expect(state.supportsDirection(.left));
    state.library_view = .all;
    try std.testing.expect(state.supportsDirection(.up));
    try std.testing.expect(state.supportsDirection(.left));
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
    library_view: ui.LibraryView = .all,
    system: ?usize = null,
    selected: usize = 0,
    game_index: usize = 0,
    library_selection: usize = 0,
    // Rich library content may settle after a held skim while focus and title
    // continue to track `selected` on every repeat.
    library_preview: usize = 0,
    // Source-library indices, distinct from filtered positions.
    last_played: ?usize = null,
    recent: [maximum_history]usize = @splat(0),
    recent_len: usize = 0,
    resumable: bool = false,
    filter_positions: [catalog.systems.len + 1]usize = @splat(0),
    /// Actionable failure attached to the currently visible task. Routine
    /// progress and success are represented by the control or device state.
    issue: []const u8 = "",
    pending_launch: ?usize = null,
    launch_failed: ?retroarch.Failure = null,
    settings: settings_model.Values = .{},
    active_setting: settings_model.Setting = .brightness,
    pending_setting: ?settings_model.Setting = null,
    pending_power: ?Power = null,
    pending_artwork: ?ArtworkRequest = null,
    artwork_title: wifi_flow.Field = .{},
    revision: u64 = 1,
    battery_percent: ?u8 = null,
    wifi: wifi_flow.Model = .{},
    wifi_fallback: captive.Snapshot = .{},
    bluetooth: bluetooth_model.Model = .{},

    pub fn collection(self: *const Model) catalog.Collection {
        return .{
            .games = self.games,
            .system = self.system,
            .order = if (self.library_view == .recent) self.recent[0..self.recent_len] else null,
        };
    }

    pub fn recordPlayed(self: *Model, source: usize) void {
        if (source >= self.games.len) return;
        const previous = self.recent;
        var destination: usize = 1;
        var index: usize = 0;
        while (index < self.recent_len and destination < self.recent.len) : (index += 1) {
            const candidate = previous[index];
            if (candidate == source) continue;
            self.recent[destination] = candidate;
            destination += 1;
        }
        self.recent[0] = source;
        self.recent_len = destination;
        self.last_played = source;
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
        if (self.games.len != 0) {
            if (self.library_view == .recent and self.recent_len == 0) self.library_view = .all;
            self.browse();
        } else {
            self.page = .foyer;
            self.selected = 0;
        }
        return null;
    }

    pub fn supportsDirection(self: *const Model, action: Action) bool {
        const vertical = action == .up or action == .down;
        const horizontal = action == .left or action == .right;
        return switch (self.page) {
            .games => vertical or horizontal,
            .game_details, .artwork_identity, .artwork_library, .artwork_unmatched => vertical,
            .artwork_title => vertical or horizontal,
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

    fn changeCollection(self: *Model, view: ?ui.LibraryView, change_system: bool, system: ?usize) void {
        const source = self.collection().sourceIndex(self.library_selection);
        if (view) |next| self.library_view = next;
        if (change_system) self.system = system;
        self.library_selection = if (source) |index| self.collection().positionOf(index) orelse 0 else 0;
        self.browse();
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
        if (action == .menu) {
            const destination = product_navigation.menuDestination(self.page) orelse return false;
            if (self.page == .games) self.remember();
            if (self.page == .wifi or self.page == .wifi_fallback) self.wifi.dismiss();
            if (self.page == .bluetooth) self.bluetooth.dismiss();
            if (self.page == .artwork_title) self.artwork_title.wipe();
            self.launch_failed = null;
            if (destination == .games)
                self.browse()
            else {
                self.page = destination;
                self.selected = 0;
            }
            self.revision += 1;
            return true;
        }
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
        if (self.page == .artwork_title) {
            if (action == .back) {
                self.artwork_title.wipe();
                self.page = .artwork_identity;
                self.selected = 1;
                self.revision += 1;
                return true;
            }
            if (action == .up or action == .down or action == .left or action == .right) {
                const changed = self.artwork_title.move(action);
                if (changed) self.revision += 1;
                return changed;
            }
            if (action == .filter) {
                self.artwork_title.wipe();
                self.revision += 1;
                return true;
            }
            if (action != .select) return false;
            switch (self.artwork_title.activate()) {
                .unchanged => return false,
                .changed => self.revision += 1,
                .submit => {
                    if (self.artwork_title.len == 0) return false;
                    var request = ArtworkRequest{ .command = .set_title, .game = self.game_index, .value_len = self.artwork_title.len };
                    @memcpy(request.value[0..request.value_len], self.artwork_title.slice());
                    self.pending_artwork = request;
                    self.page = .artwork_identity;
                    self.selected = 0;
                    self.artwork_title.wipe();
                    self.revision += 1;
                },
            }
            return true;
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
                } else if (self.page == .games) {
                    self.remember();
                    const next: ui.LibraryView = if (left) .recent else .all;
                    if (next != self.library_view) self.changeCollection(next, false, null);
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
                .game_details => if (self.selected == 0) {
                    self.pending_launch = self.game_index;
                    self.launch_failed = null;
                } else {
                    self.page = .artwork_identity;
                    self.selected = 0;
                },
                .artwork_identity => if (self.selected == 1) {
                    self.artwork_title.wipe();
                    const title = self.games[self.game_index].title;
                    const length: u8 = @intCast(@min(title.len, self.artwork_title.bytes.len));
                    @memcpy(self.artwork_title.bytes[0..length], title[0..length]);
                    self.artwork_title.len = length;
                    self.page = .artwork_title;
                } else {
                    self.pending_artwork = .{ .command = switch (self.selected) {
                        0 => .refresh_game,
                        2 => .import_local,
                        3 => .remove_game,
                        else => .reset_game,
                    }, .game = self.game_index };
                },
                .artwork_title => unreachable,
                .artwork_library => switch (self.selected) {
                    0 => self.pending_artwork = .{ .command = .refresh_missing },
                    1 => if (self.missingArtwork() != 0) {
                        self.page = .artwork_unmatched;
                        self.selected = 0;
                    },
                    else => self.pending_artwork = .{ .command = .remove_all },
                },
                .artwork_unmatched => if (self.missingSourceIndex(self.selected)) |index| {
                    self.game_index = index;
                    self.page = .artwork_identity;
                    self.selected = 0;
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
                        self.page = .artwork_library;
                        self.selected = 0;
                    } else if (self.selected == settings_count + 3) {
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
                    self.changeCollection(null, true, if (self.selected == 0) null else self.systemAt(self.selected - 1));
                },
                .views => {
                    self.changeCollection(@fromBackingInt(@intCast(self.selected)), false, null);
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
                .game_details => self.browse(),
                .artwork_identity => {
                    self.page = .game_details;
                    self.selected = 1;
                },
                .artwork_title => unreachable,
                .artwork_library => {
                    self.page = .settings;
                    self.selected = settings_count + 2;
                },
                .artwork_unmatched => {
                    self.page = .artwork_library;
                    self.selected = 1;
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
                    self.selected = settings_count + 3;
                },
                .power_confirm => {
                    self.page = .power;
                    self.selected = 2;
                },
            },
            .menu => unreachable,
            .view => if (self.page == .games) {
                self.remember();
                if (self.collection().sourceIndex(self.selected)) |index| {
                    self.game_index = index;
                    self.page = .game_details;
                    self.selected = 0;
                }
            },
            .filter => if (self.page == .games) {
                self.remember();
                self.page = .systems;
                self.selected = 0;
            },
        }
        if (self.page == .games and before_selected != self.selected) self.library_preview = self.selected;
        const changed = before_page != self.page or before_selected != self.selected or before_view != self.library_view or before_system != self.system or before_error != self.launch_failed or self.pending_launch != null or self.pending_setting != null or self.pending_power != null or self.pending_artwork != null;
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

    pub fn takeArtworkRequest(self: *Model) ?ArtworkRequest {
        const pending = self.pending_artwork;
        self.pending_artwork = null;
        return pending;
    }

    fn missingArtwork(self: *const Model) usize {
        var count: usize = 0;
        for (self.games) |game| if (game.assets.reference == null) {
            count += 1;
        };
        return count;
    }

    fn missingSourceIndex(self: *const Model, position: usize) ?usize {
        var current: usize = 0;
        for (self.games, 0..) |game, index| if (game.assets.reference == null) {
            if (current == position) return index;
            current += 1;
        };
        return null;
    }

    pub fn artworkSource(self: *const Model) ?usize {
        if (self.games.len == 0) return null;
        return switch (self.page) {
            .games => self.collection().sourceIndex(self.library_preview),
            .game, .game_details, .artwork_identity, .artwork_title => self.game_index,
            .artwork_unmatched => self.missingSourceIndex(self.selected),
            .foyer => self.last_played,
            else => null,
        };
    }

    pub fn takeWifiRequest(self: *Model) ?wifi_flow.Request {
        return self.wifi.takeRequest();
    }

    pub fn updateWifi(self: *Model, next: wifi.Snapshot) bool {
        const changed = self.wifi.update(next);
        if (changed) {
            if (self.page == .wifi or self.page == .wifi_fallback) self.issue = "";
            self.revision += 1;
        }
        return changed;
    }

    pub fn takeBluetoothCommand(self: *Model) ?bluetooth_model.Command {
        return self.bluetooth.takeCommand();
    }

    pub fn updateBluetooth(self: *Model, next: bluetooth_model.Snapshot) bool {
        const changed = self.bluetooth.update(next);
        if (changed) {
            if (self.page == .bluetooth) self.issue = "";
            self.revision += 1;
        }
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
            .game_details => 2,
            .artwork_identity => 5,
            .artwork_title => 1,
            .artwork_library => 3,
            .artwork_unmatched => self.missingArtwork(),
            .settings => settings_count + 4,
            .setting => settings_model.labels(self.active_setting).len,
            .wifi => 1,
            .wifi_fallback => 1,
            .bluetooth => 1,
            .views => 2,
            .power => 3,
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
        const theme = self.settings.appearance.colors();
        var result = switch (self.page) {
            .foyer => ui.foyerSession(theme, self.selected, if (self.last_played) |index| self.games[index] else null, self.resumable),
            .games => ui.libraryCollection(theme, self.collection(), self.selected, self.library_preview, self.library_view),
            .game => if (self.games.len == 0) ui.library(theme, self.games, 0, self.library_view) else ui.gameDetail(theme, self.games[self.game_index], self.launch_failed),
            .game_details => ui.gameInformation(theme, self.games[self.game_index], self.selected),
            .artwork_identity => ui.artworkIdentity(theme, self.games[self.game_index], self.selected, self.wifi.wifi_state.snapshot.connectivity == .internet),
            .artwork_title => ui.artworkTitle(theme, self.artwork_title.slice(), .{ .selected = self.artwork_title.selected, .uppercase = self.artwork_title.uppercase, .symbols = self.artwork_title.symbols }),
            .artwork_library => ui.artworkLibrary(theme, self.selected, self.missingArtwork(), self.games.len),
            .artwork_unmatched => ui.artworkUnmatched(theme, self.games, self.selected),
            .settings => ui.settings(self.selected, self.settings, self.wifi.wifi_state.summary(), self.bluetooth.summary()),
            .setting => ui.setting(self.active_setting, self.selected, self.settingIndex(), self.settings),
            .wifi => self.wifiTree(theme),
            .wifi_fallback => ui.wifiFallback(theme, self.wifi_fallback.url(), &self.wifi_fallback.qr),
            .bluetooth => ui.bluetooth(theme, &self.bluetooth),
            .views => ui.choice(theme, "Library density", &.{ "Recent", "All games" }, self.selected, @backingInt(self.library_view), "Choose a spacious or compact list.", "Library"),
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
            var bluetooth: ui.NetworkStatus = if (self.bluetooth.snapshot.radio == .failed) .attention else .hidden;
            for (self.bluetooth.snapshot.items()) |device| switch (device.state) {
                .connected, .preparing_audio, .ready => bluetooth = .connected,
                .nearby, .saved => {},
            };
            ui.systemStatus(&result, .{ .battery = self.battery_percent, .network = network, .bluetooth = bluetooth, .audio = self.bluetooth.snapshot.hasSelectedAudio() });
        }
        if (self.issue.len != 0) ui.taskIssue(&result, self.issue);
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
    try std.testing.expectEqual(@as(usize, 2), state.selected);
    try std.testing.expectEqual(@as(?usize, 2), state.librarySource());
}

test "horizontal direction changes collection while View opens game details" {
    var state = Model{ .page = .games, .selected = 2, .recent = .{ 0, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .recent_len = 5 };
    _ = state.apply(.left);
    try std.testing.expectEqual(ui.LibraryView.recent, state.library_view);
    try std.testing.expectEqual(Page.games, state.page);
    _ = state.apply(.right);
    try std.testing.expectEqual(ui.LibraryView.all, state.library_view);
    try std.testing.expectEqual(@as(usize, 2), state.selected);
    _ = state.apply(.view);
    try std.testing.expectEqual(Page.game_details, state.page);
    _ = state.apply(.back);
    _ = state.apply(.down);
    try std.testing.expectEqual(@as(usize, 3), state.selected);
    _ = state.apply(.down);
    try std.testing.expectEqual(@as(usize, 4), state.selected);
    try std.testing.expect(!state.apply(.down));
}

test "recent collection is ordered by actual play and de-duplicates replays" {
    var state = Model{ .page = .games, .library_view = .recent };
    state.recordPlayed(2);
    state.recordPlayed(0);
    state.recordPlayed(2);
    try std.testing.expectEqual(@as(usize, 2), state.recent_len);
    try std.testing.expectEqual(@as(?usize, 2), state.collection().sourceIndex(0));
    try std.testing.expectEqual(@as(?usize, 0), state.collection().sourceIndex(1));
    try std.testing.expectEqual(@as(?usize, 2), state.last_played);
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

test "Menu restores Library context from every Device depth" {
    var state = Model{ .page = .setting, .library_selection = 4, .selected = 2 };
    _ = state.apply(.menu);
    try std.testing.expectEqual(Page.games, state.page);
    try std.testing.expectEqual(@as(usize, 4), state.selected);
}

test "Menu dismisses Wi-Fi without retaining unfinished credentials" {
    var state = Model{ .page = .wifi, .library_selection = 3 };
    state.wifi.page = .password;
    state.wifi.field.bytes[0] = 'x';
    state.wifi.field.len = 1;
    _ = state.apply(.menu);
    try std.testing.expectEqual(Page.games, state.page);
    try std.testing.expectEqual(@as(usize, 3), state.selected);
    try std.testing.expectEqual(@as(u8, 0), state.wifi.field.len);
    try std.testing.expectEqual(@as(u8, 0), state.wifi.field.bytes[0]);
}

test "Menu rejects a Bluetooth pairing prompt before dismissing it" {
    var state = Model{ .page = .bluetooth, .library_selection = 2 };
    state.bluetooth.page = .code_entry;
    state.bluetooth.field.bytes[0] = '7';
    state.bluetooth.field.len = 1;
    _ = state.apply(.menu);
    try std.testing.expectEqual(Page.games, state.page);
    try std.testing.expectEqual(@as(usize, 2), state.selected);
    try std.testing.expectEqual(bluetooth_model.CommandKind.cancel, state.takeBluetoothCommand().?.kind);
    try std.testing.expectEqual(@as(u8, 0), state.bluetooth.field.len);
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
    var state = Model{ .page = .settings, .selected = settings_count + 3 };
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.power, state.page);
    _ = state.apply(.back);
    try std.testing.expectEqual(Page.settings, state.page);
    try std.testing.expectEqual(settings_count + 3, state.selected);
}

test "per-game artwork actions preserve immediate launch" {
    var state = Model{ .page = .games, .selected = 2 };
    _ = state.apply(.view);
    try std.testing.expectEqual(Page.game_details, state.page);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.artwork_identity, state.page);
    _ = state.apply(.select);
    const request = state.takeArtworkRequest().?;
    try std.testing.expectEqual(ArtworkCommand.refresh_game, request.command);
    try std.testing.expectEqual(@as(?usize, 2), request.game);
    _ = state.apply(.back);
    try std.testing.expectEqual(Page.game_details, state.page);
    _ = state.apply(.up);
    _ = state.apply(.select);
    try std.testing.expectEqual(@as(?usize, 2), state.takeLaunch());
}

test "artwork review is a navigable queue rather than a jump to first missing" {
    const reference = @import("artwork_store.zig").Reference{ .content_id = "ready", .path = "/ready.brtx", .source = "test" };
    const reviewed = [_]catalog.Game{
        catalog.games[0],
        catalog.games[1],
        catalog.games[2],
    };
    var mutable = reviewed;
    mutable[1].assets.reference = reference;
    var state = Model{ .games = &mutable, .page = .artwork_library, .selected = 1 };
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.artwork_unmatched, state.page);
    try std.testing.expectEqual(@as(?usize, 0), state.artworkSource());
    _ = state.apply(.down);
    try std.testing.expectEqual(@as(?usize, 2), state.artworkSource());
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.artwork_identity, state.page);
    try std.testing.expectEqual(@as(usize, 2), state.game_index);
}

test "title correction uses the controller keyboard and queues a durable override" {
    var state = Model{ .page = .artwork_identity, .game_index = 2, .selected = 1 };
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.artwork_title, state.page);
    state.artwork_title.len = 6;
    @memcpy(state.artwork_title.bytes[0..6], "Tetris");
    state.artwork_title.selected = 39;
    _ = state.apply(.select);
    const request = state.takeArtworkRequest().?;
    try std.testing.expectEqual(ArtworkCommand.set_title, request.command);
    try std.testing.expectEqualStrings("Tetris", request.valueSlice());
    try std.testing.expectEqual(Page.artwork_identity, state.page);
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

test "radio and device snapshot transitions settle without global feedback" {
    var state = Model{};
    _ = state.updateBluetooth(try bluetooth_model.parse("snapshot version=1 generation=1 revision=1 radio=starting discovery=idle operation=radio_change operation_device= prompt=none prompt_device= prompt_value=\nend\n"));
    _ = state.updateBluetooth(try bluetooth_model.parse("snapshot version=1 generation=1 revision=2 radio=ready discovery=idle operation=none operation_device= prompt=none prompt_device= prompt_value=\nend\n"));
    _ = state.updateWifi(try wifi.parse("snapshot generation=2 revision=1 radio=starting connectivity=none can_scan=0\nend\n"));
    _ = state.updateWifi(try wifi.parse("snapshot generation=2 revision=2 radio=ready connectivity=internet can_scan=1\nend\n"));
    _ = state.updateBluetooth(try bluetooth_model.parse(
        "snapshot version=1 generation=3 revision=1 radio=ready discovery=idle operation=none operation_device= prompt=none prompt_device= prompt_value=\n" ++
            "device id=headphones name_hex=4865616470686f6e6573 kind=audio state=connected battery=80 legacy=0\nend\n",
    ));
    _ = state.updateBluetooth(try bluetooth_model.parse(
        "snapshot version=1 generation=3 revision=2 radio=ready discovery=idle operation=none operation_device= prompt=none prompt_device= prompt_value=\n" ++
            "device id=headphones name_hex=4865616470686f6e6573 kind=audio state=ready battery=80 legacy=0\nend\n",
    ));
    _ = state.updateBluetooth(try bluetooth_model.parse(
        "snapshot version=1 generation=3 revision=3 radio=ready discovery=idle operation=none operation_device= prompt=none prompt_device= prompt_value=\n" ++
            "device id=headphones name_hex=4865616470686f6e6573 kind=audio state=ready battery=80 legacy=0 audio_selected=1\nend\n",
    ));
    try std.testing.expectEqualStrings("", state.issue);
}

test "routine connection success settles into the foyer status cluster" {
    var state = Model{ .page = .foyer, .last_played = 0, .resumable = true, .battery_percent = 72 };
    state.wifi.wifi_state.initialized = true;
    state.wifi.wifi_state.snapshot.radio = .ready;
    state.wifi.wifi_state.snapshot.connectivity = .internet;
    const tree = state.tree();

    var has_wifi_mark = false;
    var success_copy = false;
    for (tree.slice()) |element| switch (element) {
        .wifi => has_wifi_mark = true,
        .text => |value| success_copy = success_copy or std.mem.eql(u8, value.value, "Connected to Wi-Fi"),
        else => {},
    };
    try std.testing.expect(has_wifi_mark);
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
