// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const input = @import("input.zig");
const ui = @import("ui.zig");

pub const Layer = enum { pause, states, save_slots, replace_confirm, load_confirm, performance, failure };
pub const Command = enum { resume_game, save_state, load_state, apply_performance, network_settings, exit_game };

const pause_count = 6;
const state_count = 4;
const save_slot_count = 3;

pub const Model = struct {
    appearance: @import("theme.zig").Mode = .light,
    layer: Layer = .pause,
    selected: usize = 0,
    state_slot: usize = 0,
    save_slot: usize = 0,
    performance_profile: usize = 1,
    title: []const u8 = "Game",
    system: []const u8 = "",
    notice: []const u8 = "",
    saved: bool = false,
    available: [4]bool = @splat(false),
    pending: ?Command = null,
    confirmation: usize = 0,
    failed_command: ?Command = null,
    network_status: []const u8 = "Off",
    revision: u64 = 1,

    pub fn apply(self: *Model, action: input.Action) bool {
        const before_layer = self.layer;
        const before_confirmation = self.confirmation;
        const before_selected = self.selected;
        const before_slot = self.state_slot;
        const before_save_slot = self.save_slot;
        const before_performance = self.performance_profile;
        const before_saved = self.saved;
        const before_pending = self.pending;

        switch (self.layer) {
            .pause => self.applyPause(action),
            .states => self.applyStates(action),
            .save_slots => self.applySaveSlots(action),
            .replace_confirm, .load_confirm => {
                switch (action) {
                    .up, .down => self.confirmation = if (action == .up) 0 else 1,
                    .select => if (self.confirmation == 0) {
                        self.layer = if (self.layer == .replace_confirm) .save_slots else .states;
                    } else {
                        self.pending = if (self.layer == .replace_confirm) .save_state else .load_state;
                    },
                    .back => self.layer = if (self.layer == .replace_confirm) .save_slots else .states,
                    .menu => self.pending = .resume_game,
                    else => {},
                }
            },
            .performance => {
                switch (action) {
                    .up => self.selected -|= 1,
                    .down => self.selected = @min(2, self.selected + 1),
                    .select => {
                        self.performance_profile = self.selected;
                        self.pending = .apply_performance;
                    },
                    .back => {
                        self.layer = .pause;
                        self.selected = 3;
                    },
                    .menu => self.pending = .resume_game,
                    else => {},
                }
            },
            .failure => {
                switch (action) {
                    .up => self.confirmation = 0,
                    .down => self.confirmation = 1,
                    .select => if (self.confirmation == 1) {
                        self.pending = self.failed_command;
                    } else {
                        self.layer = .pause;
                    },
                    .back => self.layer = .pause,
                    .menu => self.pending = .resume_game,
                    else => {},
                }
            },
        }

        const changed = before_confirmation != self.confirmation or before_layer != self.layer or before_selected != self.selected or
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
        const performance_values = [_][]const u8{ "Power saver", "Balanced", "Performance" };
        return switch (self.layer) {
            .pause => ui.overlayPauseWithNetwork(self.appearance.colors(), self.title, self.selected, self.save_slot, performance_values[self.performance_profile], self.network_status, self.notice),
            .states => ui.overlayStates(self.appearance.colors(), self.title, self.state_slot, self.notice, self.available),
            .save_slots => ui.saveSlots(self.appearance.colors(), self.title, self.save_slot, self.available),
            .replace_confirm => ui.confirmation(self.appearance.colors(), "Replace saved state", "Replace this saved state?", "The existing state in this slot will be replaced.", "Replace state", self.confirmation),
            .load_confirm => ui.confirmation(self.appearance.colors(), "Load saved state", "Return to this saved state?", "Progress since that state will be lost.", "Load state", self.confirmation),
            .performance => ui.choice(self.appearance.colors(), "Performance", &performance_values, self.selected, self.performance_profile, "Balances responsiveness and power use.", "Game menu"),
            .failure => ui.confirmation(self.appearance.colors(), "Unable to save", "State was not saved", self.notice, "Try again", self.confirmation),
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
            .view, .filter => {},
            .select => switch (self.selected) {
                0 => self.pending = .resume_game,
                1 => {
                    self.saved = false;
                    self.notice = "";
                    self.layer = .save_slots;
                },
                2 => {
                    self.layer = .states;
                    self.selected = self.state_slot;
                },
                3 => {
                    self.layer = .performance;
                    self.selected = self.performance_profile;
                },
                4 => self.pending = .network_settings,
                5 => self.pending = .exit_game,
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
            .select => if (self.available[self.state_slot]) {
                self.layer = .load_confirm;
                self.confirmation = 0;
            },
            .back => {
                self.layer = .pause;
                self.selected = 2;
            },
            .menu => self.pending = .resume_game,
            .view, .filter => {},
        }
    }

    fn applySaveSlots(self: *Model, action: input.Action) void {
        switch (action) {
            .up => self.save_slot -|= 1,
            .down => self.save_slot = @min(save_slot_count - 1, self.save_slot + 1),
            .select => if (self.available[self.save_slot]) {
                self.layer = .replace_confirm;
                self.confirmation = 0;
            } else {
                self.pending = .save_state;
            },
            .back => {
                self.layer = .pause;
                self.selected = 1;
            },
            .menu => self.pending = .resume_game,
            else => {},
        }
    }
};

test "saving an occupied slot requires confirmation; cancelling preserves it" {
    var state = Model{ .selected = 1, .available = .{ true, false, false, true } };
    _ = state.apply(.select);
    try std.testing.expectEqual(Layer.save_slots, state.layer);
    _ = state.apply(.select);
    try std.testing.expectEqual(Layer.replace_confirm, state.layer);
    try std.testing.expect(state.takeCommand() == null);
    _ = state.apply(.select);
    try std.testing.expectEqual(Layer.save_slots, state.layer);
    _ = state.apply(.select);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(Command.save_state, state.takeCommand().?);
}

test "empty slots cannot load and valid loads require confirmation" {
    var state = Model{ .layer = .states, .available = .{ false, true, false, true } };
    _ = state.apply(.select);
    try std.testing.expect(state.takeCommand() == null);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(Layer.load_confirm, state.layer);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(Command.load_state, state.takeCommand().?);
}

test "back returns from submenus and Menu resumes from every layer" {
    var state = Model{ .selected = 2 };
    _ = state.apply(.select);
    _ = state.apply(.back);
    try std.testing.expectEqual(Layer.pause, state.layer);
    try std.testing.expectEqual(@as(usize, 2), state.selected);
    inline for (@typeInfo(Layer).@"enum".field_values) |value| {
        state.layer = @fromBackingInt(value);
        _ = state.apply(.menu);
        try std.testing.expectEqual(Command.resume_game, state.takeCommand().?);
    }
}
