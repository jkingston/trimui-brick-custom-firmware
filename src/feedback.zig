// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const Event = enum {
    focus_moved,
    boundary_reached,
    action_confirmed,
    action_succeeded,
    action_failed,
    warning,
};

pub const Sound = enum { none, move, boundary, confirm, success, failure, warning };
pub const Haptic = enum { none, boundary, confirm, success, failure };
pub const Cue = struct { sound: Sound = .none, haptic: Haptic = .none };

/// Hardware-independent feedback policy. Drivers consume Cue; components only
/// emit semantic Event values. Selection haptics deliberately remain off for
/// the Brick's binary motor until physical pulse qualification says otherwise.
pub const Policy = struct {
    sounds: bool = true,
    haptics: bool = true,

    pub fn cue(self: Policy, event: Event) Cue {
        const base: Cue = switch (event) {
            .focus_moved => .{ .sound = .move },
            .boundary_reached => .{ .sound = .boundary, .haptic = .boundary },
            .action_confirmed => .{ .sound = .confirm },
            .action_succeeded => .{ .sound = .success, .haptic = .success },
            .action_failed => .{ .sound = .failure, .haptic = .failure },
            .warning => .{ .sound = .warning },
        };
        return .{
            .sound = if (self.sounds) base.sound else .none,
            .haptic = if (self.haptics) base.haptic else .none,
        };
    }
};

test "feedback stays semantic and independently optional" {
    const quiet = Policy{ .sounds = false, .haptics = true };
    try std.testing.expectEqual(Sound.none, quiet.cue(.action_failed).sound);
    try std.testing.expectEqual(Haptic.failure, quiet.cue(.action_failed).haptic);
    try std.testing.expectEqual(Haptic.none, (Policy{}).cue(.focus_moved).haptic);
}
