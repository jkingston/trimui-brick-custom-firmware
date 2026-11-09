// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const capacity = 96;
pub const byte_budget = 16 * 1024 * 1024;

pub const Entry = struct {
    handle: c_uint = 0,
    key: u64 = 0,
    kind: u8 = 0,
    bytes: usize = 0,
    used: u64 = 0,
};

pub const Cache = struct {
    entries: [capacity]Entry = @splat(.{}),
    bytes: usize = 0,
    clock: u64 = 0,

    pub fn find(self: *Cache, key: u64, kind: u8) ?c_uint {
        self.clock += 1;
        for (&self.entries) |*entry| if (entry.handle != 0 and entry.key == key and entry.kind == kind) {
            entry.used = self.clock;
            return entry.handle;
        };
        return null;
    }

    pub fn victim(self: *const Cache) usize {
        var candidate: usize = 0;
        for (self.entries, 0..) |entry, index| {
            if (entry.handle == 0) return index;
            if (entry.used < self.entries[candidate].used) candidate = index;
        }
        return candidate;
    }

    pub fn oldest(self: *const Cache) ?usize {
        var result: ?usize = null;
        for (self.entries, 0..) |entry, index| {
            if (entry.handle == 0) continue;
            if (result == null or entry.used < self.entries[result.?].used) result = index;
        }
        return result;
    }

    pub fn insert(self: *Cache, index: usize, handle: c_uint, key: u64, kind: u8, bytes: usize) void {
        std.debug.assert(self.entries[index].handle == 0);
        self.entries[index] = .{ .handle = handle, .key = key, .kind = kind, .bytes = bytes, .used = self.clock };
        self.bytes += bytes;
    }

    pub fn remove(self: *Cache, index: usize) Entry {
        const old = self.entries[index];
        self.bytes -= old.bytes;
        self.entries[index] = .{};
        return old;
    }
};

test "lookup updates recency and victim prefers an empty slot" {
    var cache: Cache = .{};
    cache.insert(0, 10, 100, 1, 64);
    cache.insert(1, 11, 101, 1, 128);
    try std.testing.expectEqual(@as(c_uint, 10), cache.find(100, 1).?);
    try std.testing.expect(cache.entries[0].used > cache.entries[1].used);
    try std.testing.expectEqual(@as(usize, 2), cache.victim());
    try std.testing.expectEqual(@as(usize, 1), cache.oldest().?);
    _ = cache.remove(0);
    try std.testing.expectEqual(@as(usize, 128), cache.bytes);
}
