// SPDX-License-Identifier: GPL-2.0-only

const std = @import("std");

pub const PanResult = enum { success, no_space };
pub const Operation = union(enum) { pan: usize, synchronise: usize };

pub const Synchronizer = struct {
    page_count: usize,
    next_page: usize,
    phase: enum { walk, synchronise, reset, done } = .walk,
    waiting: bool = false,

    pub fn init(reported_page: usize, page_count: usize) !Synchronizer {
        if (page_count < 2 or reported_page >= page_count) return error.InvalidFramebufferPages;
        return .{ .page_count = page_count, .next_page = reported_page + 1 };
    }

    pub fn next(self: *Synchronizer) ?Operation {
        if (self.waiting) return null;
        const operation: Operation = switch (self.phase) {
            .walk => if (self.next_page < self.page_count)
                .{ .pan = self.next_page }
            else blk: {
                self.phase = .reset;
                break :blk .{ .pan = 0 };
            },
            .synchronise => .{ .synchronise = self.page_count - 1 },
            .reset => .{ .pan = 0 },
            .done => return null,
        };
        self.waiting = true;
        return operation;
    }

    pub fn completePan(self: *Synchronizer, result: PanResult) !void {
        if (!self.waiting or (self.phase != .walk and self.phase != .reset)) return error.UnexpectedFramebufferResult;
        self.waiting = false;
        switch (self.phase) {
            .walk => switch (result) {
                .success => self.next_page += 1,
                .no_space => self.phase = .synchronise,
            },
            .reset => switch (result) {
                .success => self.phase = .done,
                .no_space => return error.FramebufferResetFailed,
            },
            else => unreachable,
        }
    }

    pub fn completeSynchronise(self: *Synchronizer) !void {
        if (!self.waiting or self.phase != .synchronise) return error.UnexpectedFramebufferResult;
        self.waiting = false;
        self.phase = .reset;
    }
};

const FakeFramebuffer = struct {
    reported: usize,
    actual: usize,
    page_count: usize,

    fn pan(self: *FakeFramebuffer, requested: usize) PanResult {
        const target = @as(isize, @intCast(self.actual)) + @as(isize, @intCast(requested)) - @as(isize, @intCast(self.reported));
        if (target < 0 or target >= self.page_count) return .no_space;
        self.actual = @intCast(target);
        self.reported = requested;
        return .success;
    }

    fn synchronise(self: *FakeFramebuffer, page: usize) void {
        self.reported = page;
    }

    fn fbconReset(self: *FakeFramebuffer) void {
        self.reported = 0;
    }
};

fn recover(fake: *FakeFramebuffer) !void {
    var synchronizer = try Synchronizer.init(fake.reported, fake.page_count);
    while (synchronizer.next()) |operation| switch (operation) {
        .pan => |page| try synchronizer.completePan(fake.pan(page)),
        .synchronise => |page| {
            fake.synchronise(page);
            try synchronizer.completeSynchronise();
        },
    };
}

test "splash close reproduces invisible menu redraw" {
    var fake = FakeFramebuffer{ .reported = 0, .actual = 0, .page_count = 3 };
    try std.testing.expectEqual(PanResult.success, fake.pan(1));
    fake.fbconReset();
    try std.testing.expectEqual(PanResult.success, fake.pan(1));
    try std.testing.expectEqual(@as(usize, 2), fake.actual);
    try std.testing.expectEqual(PanResult.no_space, fake.pan(2));
    try std.testing.expectEqual(@as(usize, 1), fake.reported);
}

test "recovery converges every reported and actual page to zero" {
    for (0..3) |reported| for (reported..3) |actual| {
        var fake = FakeFramebuffer{ .reported = reported, .actual = actual, .page_count = 3 };
        try recover(&fake);
        try std.testing.expectEqual(@as(usize, 0), fake.reported);
        try std.testing.expectEqual(@as(usize, 0), fake.actual);
    };
}

test "every navigation redraw becomes the scanned page across reopen" {
    var fake = FakeFramebuffer{ .reported = 0, .actual = 2, .page_count = 3 };
    try recover(&fake);
    var draw_page: usize = 1;
    const actions = [_]enum { down, up, select, back }{ .down, .up, .select, .back };
    for (actions) |_| {
        try std.testing.expectEqual(PanResult.success, fake.pan(draw_page));
        try std.testing.expectEqual(draw_page, fake.actual);
        draw_page = (draw_page + 1) % fake.page_count;
    }
    fake.fbconReset();
    try recover(&fake);
    try std.testing.expectEqual(PanResult.success, fake.pan(1));
    try std.testing.expectEqual(@as(usize, 1), fake.actual);
}
