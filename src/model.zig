// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const retroarch = @import("retroarch.zig");
const catalog = @import("catalog.zig");
const input = @import("input.zig");
const settings = @import("settings.zig");
const ui = @import("ui.zig");

pub const Action = input.Action;
pub const Page = enum { home, games, game, settings };

const home_count = 2;
const settings_count = @typeInfo(settings.Setting).@"enum".field_names.len;

pub const Model = struct {
    games: []const catalog.Game = &catalog.games,
    page: Page = .games,
    library_view: ui.LibraryView = .list,
    selected: usize = 0,
    game_index: usize = 0,
    library_selection: usize = 0,
    notice: []const u8 = "",
    pending_launch: ?usize = null,
    launch_failed: ?retroarch.Failure = null,
    settings: settings.Values = .{},
    pending_setting: ?settings.Setting = null,
    revision: u64 = 1,

    pub fn apply(self: *Model, action: Action) bool {
        const before_page = self.page;
        const before_selected = self.selected;
        const before_game = self.game_index;
        const before_error = self.launch_failed;
        const before_view = self.library_view;

        switch (action) {
            .up => {
                if (self.page == .games) switch (self.library_view) {
                    .list => if (self.itemCount() > 0) {
                        self.selected -|= 1;
                    },
                    .shelf => {},
                    .grid => if (self.selected >= 4) {
                        self.selected -= 4;
                    },
                } else if (self.page != .game and self.itemCount() > 0)
                    self.selected -|= 1;
            },
            .down => {
                if (self.page == .games) switch (self.library_view) {
                    .list => if (self.itemCount() > 0) {
                        self.selected = @min(self.selected + 1, self.itemCount() - 1);
                    },
                    .shelf => {},
                    .grid => if (self.selected + 4 < self.itemCount()) {
                        self.selected += 4;
                    },
                } else if (self.page != .game and self.itemCount() > 0)
                    self.selected = @min(self.selected + 1, self.itemCount() - 1);
            },
            .left => if (self.page == .games and self.library_view == .grid and self.games.len > 0) {
                if (self.selected != 0) self.selected -= 1;
            } else if (self.page == .games and self.library_view == .shelf and self.games.len > 0) {
                if (self.selected != 0) self.selected -= 1;
            } else if (self.page == .settings and self.selected < settings_count) {
                const setting: settings.Setting = @fromBackingInt(@intCast(self.selected));
                self.settings.adjust(setting, -1);
                self.pending_setting = setting;
            },
            .right => if (self.page == .games and self.library_view == .grid and self.games.len > 0) {
                if (self.selected + 1 < self.games.len) self.selected += 1;
            } else if (self.page == .games and self.library_view == .shelf and self.games.len > 0) {
                if (self.selected + 1 < self.games.len) self.selected += 1;
            } else if (self.page == .settings and self.selected < settings_count) {
                const setting: settings.Setting = @fromBackingInt(@intCast(self.selected));
                self.settings.adjust(setting, 1);
                self.pending_setting = setting;
            },
            .select => switch (self.page) {
                .home => if (self.selected == 1) {
                    self.page = .settings;
                    self.selected = 0;
                } else {
                    self.page = .games;
                    self.selected = self.library_selection;
                },
                .games => if (self.games.len > 0) {
                    self.game_index = self.selected;
                    self.pending_launch = self.selected;
                    self.library_selection = self.selected;
                    self.launch_failed = null;
                },
                .game => {
                    self.pending_launch = self.game_index;
                    self.launch_failed = null;
                },
                .settings => {},
            },
            .back => switch (self.page) {
                .home => {
                    self.page = .games;
                    self.selected = self.library_selection;
                },
                .games => {
                    self.library_selection = self.selected;
                    self.page = .home;
                    self.selected = 0;
                },
                .game => {
                    self.page = .games;
                    self.selected = self.game_index;
                    self.launch_failed = null;
                },
                .settings => {
                    self.page = .home;
                    self.selected = 1;
                },
            },
            .menu => {
                if (self.page == .games) self.library_selection = self.selected;
                self.page = .home;
                self.selected = 0;
                self.launch_failed = null;
            },
            .view => if (self.page == .games) {
                self.library_view = switch (self.library_view) {
                    .list => .shelf,
                    .shelf => .grid,
                    .grid => .list,
                };
            },
        }

        const changed = before_page != self.page or before_selected != self.selected or
            before_game != self.game_index or before_error != self.launch_failed or before_view != self.library_view or
            self.pending_launch != null or self.pending_setting != null;
        if (changed) self.revision += 1;
        return changed;
    }

    pub fn takeLaunch(self: *Model) ?usize {
        const pending = self.pending_launch;
        self.pending_launch = null;
        if (pending) |index| {
            self.page = .games;
            self.selected = index;
        }
        return pending;
    }

    pub fn takeSetting(self: *Model) ?settings.Setting {
        const pending = self.pending_setting;
        self.pending_setting = null;
        return pending;
    }

    pub fn launchFailed(self: *Model, failure: retroarch.Failure) void {
        self.launch_failed = failure;
        self.page = .game;
        self.revision += 1;
    }

    fn itemCount(self: *const Model) usize {
        return switch (self.page) {
            .home => home_count,
            .games => self.games.len,
            .game => 1,
            .settings => settings_count,
        };
    }

    pub fn tree(self: *const Model) ui.Tree {
        return self.treeWithShelfOffset(0);
    }

    pub fn treeWithShelfOffset(self: *const Model, shelf_offset: i16) ui.Tree {
        const theme = self.settings.appearance.colors();
        var result = switch (self.page) {
            .home => ui.home(theme, self.selected),
            .games => ui.library(theme, self.games, self.selected, self.library_view, shelf_offset),
            .game => if (self.games.len == 0) ui.library(theme, self.games, 0, self.library_view, 0) else ui.gameDetail(theme, self.games[self.game_index], if (self.launch_failed) |failure| failure.message() else null),
            .settings => ui.settings(self.selected, self.settings),
        };
        if (self.notice.len != 0) ui.showNotice(&result, self.notice);
        return result;
    }
};

test "library launches directly and menu preserves selection and view" {
    var state = Model{};
    try std.testing.expectEqual(Page.games, state.page);
    _ = state.apply(.down);
    _ = state.apply(.view);
    _ = state.apply(.select);
    try std.testing.expectEqual(@as(?usize, 1), state.takeLaunch());
    _ = state.apply(.menu);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.settings, state.page);
    _ = state.apply(.back);
    _ = state.apply(.back);
    try std.testing.expectEqual(Page.games, state.page);
    try std.testing.expectEqual(@as(usize, 1), state.selected);
    try std.testing.expectEqual(ui.LibraryView.shelf, state.library_view);
}

test "empty library cannot launch and navigation clamps in every view" {
    var empty = Model{ .games = &.{} };
    _ = empty.apply(.select);
    _ = empty.apply(.up);
    try std.testing.expect(empty.takeLaunch() == null);
    _ = empty.tree();
    var state = Model{};
    for (0..20) |_| _ = state.apply(.down);
    try std.testing.expectEqual(state.games.len - 1, state.selected);
    _ = state.apply(.view);
    try std.testing.expect(!state.apply(.right));
    _ = state.apply(.view);
    try std.testing.expect(!state.apply(.right));
    _ = state.apply(.up);
    try std.testing.expectEqual(@as(usize, 0), state.selected);
}

test "launch failure is visible and retry preserves the game" {
    var state = Model{};
    _ = state.apply(.down);
    _ = state.apply(.select);
    _ = state.takeLaunch();
    state.launchFailed(.missing_core);
    try std.testing.expectEqual(Page.game, state.page);
    _ = state.tree();
    _ = state.apply(.select);
    try std.testing.expectEqual(@as(?usize, 1), state.takeLaunch());
    try std.testing.expectEqual(Page.games, state.page);
    try std.testing.expectEqual(@as(usize, 1), state.selected);
    state.launchFailed(.missing_core);
    _ = state.apply(.back);
    try std.testing.expectEqual(@as(usize, 1), state.selected);
}

test "appearance changes every page without losing game selection" {
    var state = Model{ .page = .settings, .selected = 4, .library_selection = 2 };
    try std.testing.expect(state.apply(.right));
    try std.testing.expectEqual(settings.Setting.appearance, state.takeSetting().?);
    try std.testing.expectEqual(@import("theme.zig").dark.background, state.tree().background);
    _ = state.apply(.back);
    try std.testing.expectEqual(@import("theme.zig").dark.background, state.tree().background);
    _ = state.apply(.back);
    try std.testing.expectEqual(@as(usize, 2), state.selected);
    try std.testing.expectEqual(@import("theme.zig").dark.background, state.tree().background);
}
