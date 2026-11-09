// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const composition = @import("composition.zig");
const damage = @import("damage.zig");
const kms = @import("gpu_kms.zig");

pub const Cache = struct {
    base: [kms.buffer_count]?damage.Scene = @splat(null),
    atlas: [kms.buffer_count]?damage.Scene = @splat(null),
    used: [kms.buffer_count]u64 = @splat(0),
    clock: u64 = 0,

    pub fn matches(self: *const Cache, index: usize, base: *const damage.Scene, atlas: *const damage.Scene) bool {
        const cached_base = if (self.base[index]) |*scene| scene else return false;
        const cached_atlas = if (self.atlas[index]) |*scene| scene else return false;
        return damage.Scene.changes(cached_base, base).slice().len == 0 and
            damage.Scene.changes(cached_atlas, atlas).slice().len == 0;
    }

    pub fn find(self: *const Cache, base: *const damage.Scene, atlas: *const damage.Scene) ?usize {
        for (0..kms.buffer_count) |index| if (self.matches(index, base, atlas)) return index;
        return null;
    }

    pub fn replacement(self: *const Cache, front: usize) usize {
        var candidate: usize = if (front == 0) 1 else 0;
        for (0..kms.buffer_count) |index| {
            if (index != front and self.used[index] < self.used[candidate]) candidate = index;
        }
        return candidate;
    }

    pub fn touch(self: *Cache, index: usize) void {
        self.clock += 1;
        self.used[index] = self.clock;
    }
};

test "three cached layer pairs retain every settings window" {
    const views = @import("ui.zig");
    var cache: Cache = .{};
    for ([_]usize{ 0, 3, 4 }, 0..) |selected, index| {
        var tree = views.settings(selected, .{}, "On", "Off");
        const plan = composition.split(&tree);
        cache.base[index] = damage.Scene.capture(&plan.base);
        cache.atlas[index] = damage.Scene.capture(&plan.atlas);
        try std.testing.expectEqual(index, cache.find(&cache.base[index].?, &cache.atlas[index].?).?);
    }
    for ([_]usize{ 4, 3, 0 }) |selected| {
        var tree = views.settings(selected, .{}, "On", "Off");
        const plan = composition.split(&tree);
        const base = damage.Scene.capture(&plan.base);
        const atlas = damage.Scene.capture(&plan.atlas);
        try std.testing.expect(cache.find(&base, &atlas) != null);
    }
}

test "replacement never selects the scanned-out target" {
    var cache: Cache = .{};
    cache.used = .{ 2, 0, 1 };
    try std.testing.expectEqual(@as(usize, 2), cache.replacement(1));
}
