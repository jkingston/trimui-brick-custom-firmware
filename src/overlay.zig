// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const input = @import("input.zig");
const ui = @import("ui.zig");

pub const Layer = enum { pause, states };
pub const Command = enum { resume_game, save_state, load_state, apply_performance, exit_game };

const pause_count = 5;
const state_count = 4;
const save_slot_count = 3;

pub const Model = struct {
    appearance: @import("theme.zig").Mode = .light,
    layer: Layer = .pause,
    selected: usize = 0,
    state_slot: usize = 0,
    save_slot: usize = 0,
    performance_profile: usize = 0,
    title: []const u8 = "Game",
    system: []const u8 = "",
    notice: []const u8 = "",
    saved: bool = false,
    available: [4]bool = @splat(false),
    pending: ?Command = null,
    revision: u64 = 1,

    pub fn apply(self: *Model, action: input.Action) bool {
        const before_layer = self.layer;
        const before_selected = self.selected;
        const before_slot = self.state_slot;
        const before_save_slot = self.save_slot;
        const before_performance = self.performance_profile;
        const before_saved = self.saved;
        const before_pending = self.pending;

        switch (self.layer) {
            .pause => self.applyPause(action),
            .states => self.applyStates(action),
        }

        const changed = before_layer != self.layer or before_selected != self.selected or
            before_slot != self.state_slot or before_save_slot != self.save_slot or
            before_performance != self.performance_profile or
            before_saved != self.saved or before_pending != self.pending;
        if (changed) self.revision += 1;
        return changed;
    }

    pub fn takeCommand(self: *Model) ?Command {
        const command = self.pending;
        self.pending = null;
        return command;
    }

    pub fn tree(self: *const Model) ui.Tree {
        const performance_values = [_][]const u8{ "Battery", "Balanced", "Performance" };
        return switch (self.layer) {
            .pause => ui.overlayPause(self.appearance.colors(), self.title, self.system, self.selected, self.save_slot, self.saved, performance_values[self.performance_profile], self.notice),
            .states => ui.overlayStates(self.appearance.colors(), self.title, self.state_slot, self.notice, self.available),
        };
    }

    fn applyPause(self: *Model, action: input.Action) void {
        switch (action) {
            .up => if (self.selected != 0) {
                self.selected -= 1;
            },
            .down => if (self.selected + 1 < pause_count) {
                self.selected += 1;
            },
            .left => if (self.selected == 1) {
                self.save_slot = if (self.save_slot == 0) save_slot_count - 1 else self.save_slot - 1;
                self.saved = false;
            } else if (self.selected == 3) {
                self.performance_profile = if (self.performance_profile == 0) 2 else self.performance_profile - 1;
                self.pending = .apply_performance;
            },
            .right => if (self.selected == 1) {
                self.save_slot = (self.save_slot + 1) % save_slot_count;
                self.saved = false;
            } else if (self.selected == 3) {
                self.performance_profile = (self.performance_profile + 1) % 3;
                self.pending = .apply_performance;
            },
            .back, .menu => self.pending = .resume_game,
            .view => {},
            .select => switch (self.selected) {
                0 => self.pending = .resume_game,
                1 => {
                    self.saved = false;
                    self.notice = "";
                    self.pending = .save_state;
                },
                2 => {
                    self.layer = .states;
                    self.selected = self.state_slot;
                },
                3 => {},
                4 => self.pending = .exit_game,
                else => unreachable,
            },
        }
    }

    fn applyStates(self: *Model, action: input.Action) void {
        switch (action) {
            .up => if (self.state_slot != 0) {
                self.state_slot -= 1;
            },
            .down => if (self.state_slot + 1 < state_count) {
                self.state_slot += 1;
            },
            .left, .right => {},
            .select => self.pending = .load_state,
            .back => {
                self.layer = .pause;
                self.selected = 2;
            },
            .menu => self.pending = .resume_game,
            .view => {},
        }
    }
};

test "pause actions expose commands and deeper layers" {
    var state = Model{};
    try std.testing.expect(state.apply(.down));
    try std.testing.expect(state.apply(.select));
    try std.testing.expect(!state.saved);
    try std.testing.expectEqual(Command.save_state, state.takeCommand().?);
    try std.testing.expect(state.apply(.down));
    try std.testing.expect(state.apply(.select));
    try std.testing.expectEqual(Layer.states, state.layer);
    try std.testing.expect(state.apply(.down));
    try std.testing.expectEqual(@as(usize, 1), state.state_slot);
    try std.testing.expect(state.apply(.back));
    try std.testing.expectEqual(Layer.pause, state.layer);
    try std.testing.expectEqual(@as(usize, 2), state.selected);
}

test "game menu clamps and exposes deliberate inline adjustments" {
    var state = Model{};
    try std.testing.expect(!state.apply(.up));
    try std.testing.expect(state.apply(.down));
    try std.testing.expect(state.apply(.right));
    try std.testing.expectEqual(@as(usize, 1), state.save_slot);
    try std.testing.expect(state.apply(.down));
    try std.testing.expect(state.apply(.down));
    try std.testing.expect(state.apply(.right));
    try std.testing.expectEqual(@as(usize, 1), state.performance_profile);
    try std.testing.expectEqual(Command.apply_performance, state.takeCommand().?);
}

test "back and menu resume from pause" {
    var state = Model{};
    try std.testing.expect(state.apply(.back));
    try std.testing.expectEqual(Command.resume_game, state.takeCommand().?);
    try std.testing.expect(state.apply(.menu));
    try std.testing.expectEqual(Command.resume_game, state.takeCommand().?);
}

test "menu always resumes while back preserves state browser context" {
    var state = Model{};
    state.selected = 2;
    _ = state.apply(.select);
    try std.testing.expectEqual(Layer.states, state.layer);
    try std.testing.expect(state.apply(.menu));
    try std.testing.expectEqual(Command.resume_game, state.takeCommand().?);
}
