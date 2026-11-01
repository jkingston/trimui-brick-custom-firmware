// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const catalog = @import("catalog.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");

pub const Action = input.Action;
pub const Page = enum { home, games, game, settings };

const home_count = 4;
const settings_count = 5;

pub const Model = struct {
    page: Page = .home,
    selected: usize = 0,
    game_index: usize = 0,
    pending_launch: ?usize = null,
    launch_failed: bool = false,
    revision: u64 = 1,

    pub fn apply(self: *Model, action: Action) bool {
        const before_page = self.page;
        const before_selected = self.selected;
        const before_game = self.game_index;
        const before_error = self.launch_failed;

        switch (action) {
            .up => {
                if (self.page != .game)
                    self.selected = if (self.selected == 0) self.itemCount() - 1 else self.selected - 1;
            },
            .down => {
                if (self.page != .game)
                    self.selected = (self.selected + 1) % self.itemCount();
            },
            .left => {},
            .right => {},
            .select => switch (self.page) {
                .home => if (self.selected == 3) {
                    self.page = .settings;
                    self.selected = 0;
                } else {
                    self.page = .games;
                    self.selected = if (self.selected == 0) 0 else @min(self.game_index, catalog.games.len - 1);
                },
                .games => {
                    self.game_index = self.selected;
                    self.page = .game;
                    self.launch_failed = false;
                },
                .game => {
                    self.pending_launch = self.game_index;
                    self.launch_failed = false;
                },
                .settings => {},
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
                    self.launch_failed = false;
                },
                .settings => {
                    self.page = .home;
                    self.selected = 3;
                },
            },
            .menu => {
                self.page = .home;
                self.selected = 0;
                self.launch_failed = false;
            },
        }

        const changed = before_page != self.page or before_selected != self.selected or
            before_game != self.game_index or before_error != self.launch_failed or self.pending_launch != null;
        if (changed) self.revision += 1;
        return changed;
    }

    pub fn takeLaunch(self: *Model) ?usize {
        const pending = self.pending_launch;
        self.pending_launch = null;
        return pending;
    }

    pub fn launchFailed(self: *Model) void {
        self.launch_failed = true;
        self.revision += 1;
    }

    fn itemCount(self: *const Model) usize {
        return switch (self.page) {
            .home => home_count,
            .games => catalog.games.len,
            .game => 1,
            .settings => settings_count,
        };
    }

    pub fn tree(self: *const Model) ui.Tree {
        return switch (self.page) {
            .home => ui.home(self.selected),
            .games => ui.library(self.selected),
            .game => ui.gameDetail(self.game_index, self.launch_failed),
            .settings => ui.settings(self.selected),
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
