// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const retroarch = @import("retroarch.zig");
const catalog = @import("catalog.zig");
const input = @import("input.zig");
const settings = @import("settings.zig");
const ui = @import("ui.zig");

pub const Action = input.Action;
pub const Page = enum { home, games, game, settings };

const home_count = 4;
const settings_count = 5;

pub const Model = struct {
    games: []const catalog.Game = &catalog.games,
    page: Page = .home,
    selected: usize = 0,
    game_index: usize = 0,
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

        switch (action) {
            .up => {
                if (self.page != .game and self.itemCount() > 0)
                    self.selected = if (self.selected == 0) self.itemCount() - 1 else self.selected - 1;
            },
            .down => {
                if (self.page != .game and self.itemCount() > 0)
                    self.selected = (self.selected + 1) % self.itemCount();
            },
            .left => if (self.page == .settings and self.selected < 4) {
                const setting: settings.Setting = @fromBackingInt(@intCast(self.selected));
                self.settings.adjust(setting, -1);
                self.pending_setting = setting;
            },
            .right => if (self.page == .settings and self.selected < 4) {
                const setting: settings.Setting = @fromBackingInt(@intCast(self.selected));
                self.settings.adjust(setting, 1);
                self.pending_setting = setting;
            },
            .select => switch (self.page) {
                .home => if (self.selected == 3) {
                    self.page = .settings;
                    self.selected = 0;
                } else {
                    self.page = .games;
                    self.selected = if (self.selected == 0) 0 else if (self.games.len == 0) 0 else @min(self.game_index, self.games.len - 1);
                },
                .games => if (self.games.len > 0) {
                    self.game_index = self.selected;
                    self.page = .game;
                    self.launch_failed = null;
                },
                .game => {
                    self.pending_launch = self.game_index;
                    self.launch_failed = null;
                },
                .settings => if (self.selected < 4) {
                    const setting: settings.Setting = @fromBackingInt(@intCast(self.selected));
                    self.settings.adjust(setting, 1);
                    self.pending_setting = setting;
                },
            },
            .back => switch (self.page) {
                .home => {},
                .games => {
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
                    self.selected = 3;
                },
            },
            .menu => {
                self.page = .home;
                self.selected = 0;
                self.launch_failed = null;
            },
        }

        const changed = before_page != self.page or before_selected != self.selected or
            before_game != self.game_index or before_error != self.launch_failed or
            self.pending_launch != null or self.pending_setting != null;
        if (changed) self.revision += 1;
        return changed;
    }

    pub fn takeLaunch(self: *Model) ?usize {
        const pending = self.pending_launch;
        self.pending_launch = null;
        return pending;
    }

    pub fn takeSetting(self: *Model) ?settings.Setting {
        const pending = self.pending_setting;
        self.pending_setting = null;
        return pending;
    }

    pub fn launchFailed(self: *Model, failure: retroarch.Failure) void {
        self.launch_failed = failure;
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
        return switch (self.page) {
            .home => ui.home(self.selected),
            .games => ui.library(self.games, self.selected),
            .game => ui.gameDetail(self.games[self.game_index], if (self.launch_failed) |failure| failure.message() else null),
            .settings => ui.settings(self.selected, self.settings),
        };
    }
};

test "home, library, detail and launch flow" {
    var state = Model{};
    try std.testing.expect(state.apply(.select));
    try std.testing.expectEqual(Page.games, state.page);
    try std.testing.expect(state.apply(.down));
    try std.testing.expect(state.apply(.select));
    try std.testing.expectEqual(Page.game, state.page);
    try std.testing.expectEqual(@as(usize, 1), state.game_index);
    try std.testing.expect(state.apply(.select));
    try std.testing.expectEqual(@as(?usize, 1), state.takeLaunch());
    try std.testing.expect(state.takeLaunch() == null);
}

test "navigation wraps and back preserves context" {
    var state = Model{};
    try std.testing.expect(state.apply(.up));
    try std.testing.expectEqual(@as(usize, 3), state.selected);
    try std.testing.expect(state.apply(.select));
    try std.testing.expectEqual(Page.settings, state.page);
    try std.testing.expect(state.apply(.back));
    try std.testing.expectEqual(Page.home, state.page);
    try std.testing.expectEqual(@as(usize, 3), state.selected);
}

test "empty library navigation cannot launch or underflow" {
    var state = Model{ .games = &.{} };
    _ = state.apply(.select);
    _ = state.apply(.up);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.games, state.page);
    try std.testing.expect(state.takeLaunch() == null);
    _ = state.tree();
}

test "large libraries render a bounded window around selection" {
    const entries: [100]catalog.Game = @splat(catalog.games[0]);
    var state = Model{ .games = &entries, .page = .games, .selected = 99 };
    const tree = state.tree();
    try std.testing.expect(tree.len < tree.elements.len);
    _ = state.apply(.down);
    try std.testing.expectEqual(@as(usize, 0), state.selected);
}

test "launch errors remain visible until retry or leaving details" {
    var state = Model{ .page = .game };
    state.launchFailed(.missing_core);
    try std.testing.expectEqual(@as(?retroarch.Failure, .missing_core), state.launch_failed);
    const tree = state.tree();
    var found = false;
    for (tree.slice()) |element| switch (element) {
        .text => |text| if (std.mem.eql(u8, text.value, "EMULATOR NOT INSTALLED")) {
            found = true;
        },
        else => {},
    };
    try std.testing.expect(found);
    _ = state.apply(.select);
    try std.testing.expect(state.launch_failed == null);
    try std.testing.expectEqual(@as(?usize, 0), state.takeLaunch());
    state.launchFailed(.save_storage);
    _ = state.apply(.back);
    try std.testing.expect(state.launch_failed == null);
    try std.testing.expectEqual(Page.games, state.page);
}
