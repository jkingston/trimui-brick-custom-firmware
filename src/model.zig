// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const retroarch = @import("retroarch.zig");
const catalog = @import("catalog.zig");
const input = @import("input.zig");
const settings_model = @import("settings.zig");
const ui = @import("ui.zig");

pub const Action = input.Action;
pub const Page = enum { home, games, game, settings, setting, systems, views, power, power_confirm };
pub const Power = enum { screen_off, suspend_device, shutdown };
const columns = @import("design.zig").geometry.grid_columns;
const settings_count = @typeInfo(settings_model.Setting).@"enum".field_names.len;

pub const Model = struct {
    games: []const catalog.Game = &catalog.games,
    page: Page = .home,
    library_view: ui.LibraryView = .list,
    system: ?usize = null,
    selected: usize = 0,
    game_index: usize = 0,
    library_selection: usize = 0,
    // Source-library indices, distinct from filtered positions.
    last_played: ?usize = null,
    resumable: bool = false,
    filter_positions: [catalog.systems.len + 1]usize = @splat(0),
    notice: []const u8 = "",
    pending_launch: ?usize = null,
    launch_failed: ?retroarch.Failure = null,
    settings: settings_model.Values = .{},
    active_setting: settings_model.Setting = .brightness,
    pending_setting: ?settings_model.Setting = null,
    pending_power: ?Power = null,
    revision: u64 = 1,
    battery_percent: ?u8 = null,

    pub fn collection(self: *const Model) catalog.Collection {
        return .{ .games = self.games, .system = self.system };
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
    }

    fn settingIndex(self: *const Model) usize {
        return switch (self.active_setting) {
            .brightness => self.settings.brightness,
            .performance => @backingInt(self.settings.performance),
            .appearance => @backingInt(self.settings.appearance),
            .display_timeout => self.settings.display_timeout,
            .suspend_timeout => self.settings.suspend_timeout,
        };
    }

    fn chooseSetting(self: *Model) void {
        switch (self.active_setting) {
            .brightness => self.settings.brightness = @intCast(self.selected),
            .performance => self.settings.performance = @fromBackingInt(@intCast(self.selected)),
            .appearance => self.settings.appearance = @fromBackingInt(@intCast(self.selected)),
            .display_timeout => self.settings.display_timeout = @intCast(self.selected),
            .suspend_timeout => self.settings.suspend_timeout = @intCast(self.selected),
        }
        self.pending_setting = self.active_setting;
    }

    pub fn apply(self: *Model, action: Action) bool {
        const before_page = self.page;
        const before_selected = self.selected;
        const before_view = self.library_view;
        const before_system = self.system;
        const before_error = self.launch_failed;
        switch (action) {
            .up, .down => {
                const up = action == .up;
                if (self.page == .games and self.library_view == .shelf) return false;
                if (self.page == .setting and self.active_setting == .brightness) return false;
                const step: usize = if (self.page == .games and self.library_view == .grid) columns else 1;
                if (up) {
                    if (step == 1 or self.selected >= step) self.selected -|= step;
                } else if (self.page != .games or self.library_view != .grid or (self.selected / columns + 1) * columns < self.itemCount()) {
                    self.selected = @min(self.selected + step, self.itemCount() -| 1);
                }
            },
            .left, .right => {
                const left = action == .left;
                if (self.page == .games and self.library_view != .list) {
                    if (left and (self.library_view == .shelf or self.selected % columns != 0)) self.selected -|= 1;
                    if (!left and (self.library_view == .shelf or self.selected % columns + 1 < columns)) self.selected = @min(self.selected + 1, self.itemCount() -| 1);
                } else if (self.page == .setting and self.active_setting == .brightness) {
                    self.selected = if (left) self.selected -| 1 else @min(self.selected + 1, 10);
                    if (self.selected != before_selected) self.chooseSetting();
                } else if (self.page == .settings) {
                    const setting: settings_model.Setting = @fromBackingInt(@intCast(self.selected));
                    self.settings.adjust(setting, if (left) -1 else 1);
                    self.pending_setting = setting;
                }
            },
            .select => switch (self.page) {
                .home => {
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
                    self.pending_launch = self.game_index;
                    self.launch_failed = null;
                },
                .settings => {
                    self.active_setting = @fromBackingInt(@intCast(self.selected));
                    self.page = .setting;
                    self.selected = self.settingIndex();
                },
                .setting => self.chooseSetting(),
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
                .home => self.browse(),
                .games => {
                    self.remember();
                    self.page = .home;
                    self.selected = 0;
                },
                .game => {
                    self.browse();
                    self.launch_failed = null;
                },
                .settings => {
                    self.page = .home;
                    self.selected = if (self.last_played != null) 2 else 1;
                },
                .setting => {
                    self.page = .settings;
                    self.selected = @backingInt(self.active_setting);
                },
                .systems, .views => self.browse(),
                .power => {
                    self.page = .home;
                    self.selected = 0;
                },
                .power_confirm => {
                    self.page = .power;
                    self.selected = 2;
                },
            },
            .menu => {
                self.remember();
                self.page = if (self.page == .home) .power else .home;
                self.selected = 0;
                self.launch_failed = null;
            },
            .view => if (self.page == .games) {
                self.remember();
                self.page = .views;
                self.selected = @backingInt(self.library_view);
            },
            .filter => if (self.page == .games) {
                self.remember();
                self.page = .systems;
                self.selected = 0;
            },
        }
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
            .home => if (self.last_played != null) 3 else 2,
            .games => self.collection().len(),
            .game => 1,
            .settings => settings_count,
            .setting => settings_model.labels(self.active_setting).len,
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
            .home => ui.homeSession(theme, self.selected, if (self.last_played) |index| self.games[index] else null, self.resumable),
            .games => ui.libraryCollection(theme, self.collection(), self.selected, self.library_view, shelf_offset),
            .game => if (self.games.len == 0) ui.library(theme, self.games, 0, self.library_view, 0) else ui.gameDetail(theme, self.games[self.game_index], if (self.launch_failed) |failure| failure.message() else null),
            .settings => ui.settings(self.selected, self.settings),
            .setting => ui.setting(self.active_setting, self.selected, self.settingIndex(), self.settings),
            .views => ui.choice(theme, "View", &.{ "List", "Cartridge flow", "Grid" }, self.selected, @backingInt(self.library_view), "", "Games"),
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
            .power => ui.choice(theme, "Power", &.{ "Turn screen off", "Sleep", "Shut down" }, self.selected, null, "Sleep disconnects Bluetooth devices.", "Home"),
            .power_confirm => ui.confirmation(theme, "Shut down", "Turn off the device?", "Hold Power to start it again.", "Shut down", self.selected),
        };
        if (self.page == .home) {
            if (self.battery_percent) |percent| result.add(.{ .battery = .{ .bounds = .{ .x = 916, .y = 40, .width = 60, .height = 28 }, .percent = percent } });
        }
        if (self.notice.len != 0) ui.showNotice(&result, self.notice);
        return result;
    }
};

test "Home opens Games and returns without losing browsing position" {
    var state = Model{};
    try std.testing.expectEqual(Page.home, state.page);
    _ = state.apply(.select);
    _ = state.apply(.down);
    _ = state.apply(.back);
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.games, state.page);
    try std.testing.expectEqual(@as(usize, 1), state.selected);
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

test "view picker retains selection and grid navigation respects row edges" {
    var state = Model{ .page = .games, .selected = 2 };
    _ = state.apply(.view);
    _ = state.apply(.down);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(ui.LibraryView.grid, state.library_view);
    try std.testing.expectEqual(@as(usize, 2), state.selected);
    try std.testing.expect(!state.apply(.right));
    _ = state.apply(.down);
    try std.testing.expectEqual(@as(usize, 4), state.selected);
    try std.testing.expect(!state.apply(.down));
    _ = state.apply(.left);
    try std.testing.expectEqual(@as(usize, 3), state.selected);
    try std.testing.expect(!state.apply(.left));
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
    state.launchFailed(.missing_core);
    _ = state.apply(.select);
    try std.testing.expectEqual(@as(?usize, 4), state.takeLaunch());
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
