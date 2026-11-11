// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const Id = enum(u64) {
    none = 0,
    _,

    pub const Scope = enum(u32) {
        implicit_menu,
        implicit_overlay,
        implicit_frame,
        home,
        settings,
        library,
        choice,
        game_menu,
        game_menu_network,
        test_scope,
    };

    pub fn scoped(scope: Scope, index: usize) Id {
        const item: u32 = @intCast(index + 1);
        return @fromBackingInt((@as(u64, @backingInt(scope)) + 1) << 32 | item);
    }
};

pub const State = enum {
    idle,
    focused,
    pressed,
    activating,
    busy,
    succeeded,
    failed,
    disabled,

    pub fn hasFocus(self: State) bool {
        return switch (self) {
            .focused, .pressed, .activating, .busy, .succeeded, .failed => true,
            .idle, .disabled => false,
        };
    }

    pub fn acceptsInput(self: State) bool {
        return self == .idle or self == .focused or self == .pressed;
    }
};

/// Shared action lifecycle for rows, tiles, settings and asynchronous work.
/// Invalid transitions are ignored so a delayed completion cannot revive an
/// action that has already been cancelled and reset.
pub const Control = struct {
    id: Id = .none,
    state: State = .idle,

    pub fn focus(self: *Control) void {
        if (self.state == .idle) self.state = .focused;
    }

    pub fn blur(self: *Control) void {
        if (self.state == .focused or self.state == .pressed) self.state = .idle;
    }

    pub fn press(self: *Control) bool {
        if (self.state != .focused) return false;
        self.state = .pressed;
        return true;
    }

    pub fn activate(self: *Control) bool {
        if (self.state != .pressed and self.state != .focused) return false;
        self.state = .activating;
        return true;
    }

    pub fn busy(self: *Control) void {
        if (self.state == .activating) self.state = .busy;
    }

    pub fn complete(self: *Control, succeeded: bool) void {
        if (self.state == .activating or self.state == .busy)
            self.state = if (succeeded) .succeeded else .failed;
    }

    pub fn reset(self: *Control, focused: bool) void {
        self.state = if (focused) .focused else .idle;
    }
};

pub const Move = enum { previous, next };
pub const FocusResult = enum { moved, boundary, empty };

/// Selection mechanics shared by vertical lists, shelves and one-dimensional
/// control groups. Layout chooses how previous/next maps to physical direction.
pub const FocusGroup = struct {
    selected: usize = 0,
    count: usize = 0,
    wraps: bool = false,

    pub fn move(self: *FocusGroup, direction: Move) FocusResult {
        if (self.count == 0) return .empty;
        const before = self.selected;
        switch (direction) {
            .previous => if (self.selected != 0) {
                self.selected -= 1;
            } else if (self.wraps) {
                self.selected = self.count - 1;
            },
            .next => if (self.selected + 1 < self.count) {
                self.selected += 1;
            } else if (self.wraps) {
                self.selected = 0;
            },
        }
        return if (before == self.selected) .boundary else .moved;
    }
};

test "action lifecycle distinguishes press work and result" {
    var control = Control{ .id = Id.scoped(.settings, 1) };
    control.focus();
    try std.testing.expect(control.press());
    try std.testing.expect(control.activate());
    control.busy();
    control.complete(false);
    try std.testing.expectEqual(State.failed, control.state);
    control.reset(true);
    try std.testing.expectEqual(State.focused, control.state);
}

test "focus groups report boundaries instead of silent ignored input" {
    var group = FocusGroup{ .count = 3 };
    try std.testing.expectEqual(FocusResult.boundary, group.move(.previous));
    try std.testing.expectEqual(FocusResult.moved, group.move(.next));
    group.selected = 2;
    try std.testing.expectEqual(FocusResult.boundary, group.move(.next));
}

test "stable ids include scope and item" {
    try std.testing.expect(Id.scoped(.home, 0) != Id.scoped(.home, 1));
    try std.testing.expect(Id.scoped(.home, 0) != Id.scoped(.choice, 0));
    try std.testing.expectEqual(Id.scoped(.home, 0), Id.scoped(.home, 0));
}
