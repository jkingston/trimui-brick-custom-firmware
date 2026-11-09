// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const Buffers = struct {
    front: usize = 0,
    queued: ?usize = null,

    pub fn back(self: Buffers) !usize {
        if (self.queued != null) return error.FramePending;
        return 1 - self.front;
    }

    pub fn queue(self: *Buffers, index: usize) !void {
        if (index != try self.back()) return error.InvalidBackBuffer;
        self.queued = index;
    }

    pub fn complete(self: *Buffers) !void {
        self.front = self.queued orelse return error.NoPendingFrame;
        self.queued = null;
    }
};

test "neither scanout buffer is writable while a flip is pending" {
    var buffers = Buffers{};
    try std.testing.expectError(error.InvalidBackBuffer, buffers.queue(0));
    try std.testing.expectError(error.NoPendingFrame, buffers.complete());
    for (0..300) |_| {
        const previous = buffers.front;
        const back = try buffers.back();
        try buffers.queue(back);
        try std.testing.expectEqual(previous, buffers.front);
        try std.testing.expectError(error.FramePending, buffers.back());
        try std.testing.expectError(error.FramePending, buffers.queue(back));
        try buffers.complete();
        try std.testing.expectEqual(back, buffers.front);
        try std.testing.expectEqual(previous, try buffers.back());
    }
}
