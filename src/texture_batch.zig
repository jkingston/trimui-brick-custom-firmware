// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const capacity = 8;
pub const Batch = struct {
    textures: [capacity]u32 = @splat(0),
    len: usize = 0,

    pub fn slot(self: *Batch, texture: u32) ?u8 {
        for (self.textures[0..self.len], 0..) |handle, index| if (handle == texture) return @intCast(index);
        if (self.len == capacity) return null;
        const index = self.len;
        self.textures[index] = texture;
        self.len += 1;
        return @intCast(index);
    }
};

test "texture slots stay stable until a full batch is submitted" {
    var batch = Batch{};
    for (1..capacity + 1) |handle| try std.testing.expectEqual(@as(u8, @intCast(handle - 1)), batch.slot(@intCast(handle)).?);
    try std.testing.expectEqual(@as(u8, 0), batch.slot(1).?);
    try std.testing.expectEqual(@as(?u8, null), batch.slot(99));
    try std.testing.expectEqual(capacity, batch.len);
    batch.len = 0;
    try std.testing.expectEqual(@as(u8, 0), batch.slot(99).?);
    try std.testing.expectEqual(@as(u8, 1), batch.slot(1).?);
}
