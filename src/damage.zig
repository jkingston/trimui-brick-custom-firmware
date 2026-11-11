// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const ui = @import("ui_scene.zig");

pub const maximum_rects = 12;
pub const RectSet = struct {
    rects: [maximum_rects]ui.Rect = @splat(.{ .x = 0, .y = 0, .width = 0, .height = 0 }),
    len: usize = 0,
    full: bool = false,

    pub fn all() RectSet {
        return .{ .full = true };
    }

    pub fn slice(self: *const RectSet) []const ui.Rect {
        if (self.full) return &.{.{ .x = 0, .y = 0, .width = 1024, .height = 768 }};
        return self.rects[0..self.len];
    }

    pub fn add(self: *RectSet, rect: ui.Rect) void {
        if (self.full or rect.width == 0 or rect.height == 0) return;
        var merged = rect;
        var index: usize = 0;
        while (index < self.len) {
            if (!touches(merged, self.rects[index])) {
                index += 1;
                continue;
            }
            merged = unite(merged, self.rects[index]);
            self.len -= 1;
            self.rects[index] = self.rects[self.len];
            index = 0;
        }
        if (self.len == maximum_rects) {
            self.* = all();
            return;
        }
        self.rects[self.len] = merged;
        self.len += 1;
    }

    pub fn addSet(self: *RectSet, other: *const RectSet) void {
        if (other.full) {
            self.* = all();
            return;
        }
        for (other.rects[0..other.len]) |rect| self.add(rect);
    }
};

fn right(rect: ui.Rect) u32 {
    return @as(u32, rect.x) + rect.width;
}

fn bottom(rect: ui.Rect) u32 {
    return @as(u32, rect.y) + rect.height;
}

fn touches(a: ui.Rect, b: ui.Rect) bool {
    return @as(u32, a.x) < right(b) and @as(u32, b.x) < right(a) and
        @as(u32, a.y) < bottom(b) and @as(u32, b.y) < bottom(a);
}

fn unite(a: ui.Rect, b: ui.Rect) ui.Rect {
    const x = @min(a.x, b.x);
    const y = @min(a.y, b.y);
    return .{
        .x = x,
        .y = y,
        .width = @intCast(@max(right(a), right(b)) - x),
        .height = @intCast(@max(bottom(a), bottom(b)) - y),
    };
}

pub fn intersects(a: ui.Rect, b: ui.Rect) bool {
    return @as(u32, a.x) < right(b) and @as(u32, b.x) < right(a) and
        @as(u32, a.y) < bottom(b) and @as(u32, b.y) < bottom(a);
}

pub fn intersection(a: ui.Rect, b: ui.Rect) ?ui.Rect {
    if (!intersects(a, b)) return null;
    const x = @max(a.x, b.x);
    const y = @max(a.y, b.y);
    return .{ .x = x, .y = y, .width = @intCast(@min(right(a), right(b)) - x), .height = @intCast(@min(bottom(a), bottom(b)) - y) };
}

pub fn containsPixel(rects: []const ui.Rect, x: usize, y: usize) bool {
    if (rects.len == 0) return true;
    for (rects) |rect| if (x >= rect.x and x < right(rect) and y >= rect.y and y < bottom(rect)) return true;
    return false;
}

pub const Signature = [2]u64;
const Hasher = struct {
    first: std.hash.Wyhash = std.hash.Wyhash.init(0x6a09e667f3bcc909),
    second: std.hash.Wyhash = std.hash.Wyhash.init(0xbb67ae8584caa73b),
    buffer: [256]u8 = @splat(0),
    used: usize = 0,

    fn update(self: *Hasher, bytes: []const u8) void {
        var rest = bytes;
        while (rest.len != 0) {
            const count = @min(rest.len, self.buffer.len - self.used);
            @memcpy(self.buffer[self.used..][0..count], rest[0..count]);
            self.used += count;
            rest = rest[count..];
            if (self.used == self.buffer.len) self.flush();
        }
    }

    fn flush(self: *Hasher) void {
        self.first.update(self.buffer[0..self.used]);
        self.second.update(self.buffer[0..self.used]);
        self.used = 0;
    }

    fn final(self: *Hasher) Signature {
        self.flush();
        return .{ self.first.final(), self.second.final() };
    }
};
const Part = struct {
    signature: Signature = @splat(0),
    bounds: ui.Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
};
const Node = struct {
    signature: Signature = @splat(0),
    bounds: ui.Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    background: Signature = @splat(0),
    parts: ?[3]Part = null,
    keyboard: ?ui.Keyboard = null,
};

pub const Scene = struct {
    theme: ui.Theme,
    background: ui.Color,
    preserve_background: bool,
    nodes: [ui.maximum_elements]Node = @splat(.{}),
    len: usize,

    pub fn capture(tree: *const ui.Tree) Scene {
        return captureAfter(tree, null);
    }

    pub fn captureAfter(tree: *const ui.Tree, previous: ?*const Scene) Scene {
        var result = Scene{
            .theme = tree.theme,
            .background = tree.background,
            .preserve_background = tree.preserve_background,
            .len = tree.len,
        };
        for (tree.slice(), 0..) |element, index| {
            const node = &result.nodes[index];
            node.* = .{ .signature = fingerprint(element), .bounds = paintBounds(element) };
            if (previous) |old| if (index < old.len and std.meta.eql(node.signature, old.nodes[index].signature)) {
                node.* = old.nodes[index];
                continue;
            };
            if (element == .overlay_row) {
                const row = element.overlay_row;
                node.background = fingerprint(.{ .bar = .{ .bounds = row.bounds, .color = row.style.background, .radius = @import("design.zig").geometry.radius } });
                // The shared editorial baseline is rendered with the row but
                // is not one of its text-layout parts. A focus change must
                // invalidate the full row even when its fill remains quiet.
                if (row.state.hasFocus()) node.background[0] ^= 0x9e3779b97f4a7c15;
                var parts: [3]Part = @splat(.{});
                for (@import("row_layout.zig").overlay(row), &parts) |part, *saved| {
                    saved.* = .{ .signature = fingerprint(.{ .text = part }), .bounds = textBounds(part) };
                }
                node.parts = parts;
            }
            if (element == .keyboard) node.keyboard = element.keyboard;
        }
        return result;
    }

    pub fn changes(previous: ?*const Scene, next: *const Scene) RectSet {
        const old = previous orelse return RectSet.all();
        if (!std.meta.eql(old.theme, next.theme) or !std.meta.eql(old.background, next.background) or old.preserve_background != next.preserve_background)
            return RectSet.all();
        var result = RectSet{};
        const shared = @min(old.len, next.len);
        for (0..shared) |index| {
            if (!std.meta.eql(old.nodes[index].signature, next.nodes[index].signature)) {
                if (old.nodes[index].keyboard) |before| if (next.nodes[index].keyboard) |after| {
                    if (std.meta.eql(before.bounds, after.bounds) and before.uppercase == after.uppercase and before.symbols == after.symbols) {
                        result.add(before.displayedBounds());
                        result.add(after.displayedBounds());
                        continue;
                    }
                };
                if (old.nodes[index].parts) |before| if (next.nodes[index].parts) |after| {
                    if (std.meta.eql(old.nodes[index].background, next.nodes[index].background)) {
                        for (before, after) |a, b| if (!std.meta.eql(a.signature, b.signature)) {
                            result.add(a.bounds);
                            result.add(b.bounds);
                        };
                        continue;
                    }
                };
                result.add(old.nodes[index].bounds);
                result.add(next.nodes[index].bounds);
            }
        }
        for (shared..old.len) |index| result.add(old.nodes[index].bounds);
        for (shared..next.len) |index| result.add(next.nodes[index].bounds);
        return result;
    }
};

fn textBounds(text: ui.Text) ui.Rect {
    if (text.value.len == 0) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const mask = @import("text_pango.zig").rasterize(text.value, text.font, text.bounds.width, text.bounds.height) orelse return text.bounds;
    return .{ .x = text.bounds.x + mask.x, .y = text.bounds.y + mask.y, .width = mask.width, .height = mask.height };
}

pub const PageTracker = struct {
    pending: [3]RectSet = @splat(RectSet{}),
    page_count: usize,

    pub fn init(page_count: usize) !PageTracker {
        if (page_count < 2 or page_count > 3) return error.UnsupportedPageCount;
        return .{ .page_count = page_count };
    }

    pub fn invalidate(self: *PageTracker, changed: *const RectSet) void {
        for (self.pending[0..self.page_count]) |*page| page.addSet(changed);
    }

    pub fn take(self: *PageTracker, page: usize) RectSet {
        const result = self.pending[page];
        self.pending[page] = .{};
        return result;
    }
};

pub fn paintBounds(element: ui.Element) ui.Rect {
    return switch (element) {
        .bar => |value| value.bounds,
        .scrim => |value| value.bounds,
        .text => |value| value.bounds,
        .text_block => |value| value.bounds,
        .focus_frame => |value| focusBounds(value.bounds, value.displayedBounds()),
        .menu_row => |value| focusBounds(value.bounds, value.displayedBounds()),
        .action_card => |value| focusBounds(value.bounds, value.displayedBounds()),
        .battery => |value| value.bounds,
        .wifi => |value| value.bounds,
        .meter => |value| value.bounds,
        .activity => |value| value.bounds,
        .qr_code => |value| value.bounds,
        .keyboard => |value| value.bounds,
        .keyboard_key => |value| value.bounds,
        .cover => |value| expand(value.bounds, 10, 12),
        .cartridge => |value| blk: {
            var bounds = expand(value.displayBounds(), 8, 10);
            const left = bounds.x -| value.clip_left;
            bounds.width +|= bounds.x - left;
            bounds.x = left;
            break :blk bounds;
        },
        .overlay_row => |value| blk: {
            // A two-line Wi-Fi row is 88 px high, but its 52+6+40 px
            // label/detail layout extends below the opaque row background.
            const font = @import("design.zig").typeface;
            const text_height = font.body.line_height + if (value.detail.len != 0) font.caption.line_height + @as(u16, 6) else @as(u16, 0);
            break :blk expand(focusBounds(value.bounds, value.displayedBounds()), 0, text_height -| value.bounds.height);
        },
    };
}

fn focusBounds(logical: ui.Rect, displayed: ui.Rect) ui.Rect {
    const x = @min(logical.x, displayed.x);
    const y = @min(logical.y, displayed.y);
    const far_right = @max(@as(u32, logical.x) + logical.width, @as(u32, displayed.x) + displayed.width);
    const far_bottom = @max(@as(u32, logical.y) + logical.height, @as(u32, displayed.y) + displayed.height + 3);
    return .{
        .x = x,
        .y = y,
        .width = @intCast(@min(@as(u32, 1024 - x), far_right - x)),
        .height = @intCast(@min(@as(u32, 768 - y), far_bottom - y)),
    };
}

fn expand(rect: ui.Rect, x: u16, y: u16) ui.Rect {
    return .{
        .x = rect.x,
        .y = rect.y,
        // Shelf neighbours may be wholly outside the viewport while entering or
        // leaving cartridge flow. Such elements paint no pixels; their damage
        // bounds must not underflow merely because their origin is off-screen.
        .width = @intCast(@min(@as(u32, 1024 -| rect.x), @as(u32, rect.width) + x)),
        .height = @intCast(@min(@as(u32, 768 -| rect.y), @as(u32, rect.height) + y)),
    };
}

fn fingerprint(element: ui.Element) Signature {
    var hash = Hasher{};
    const tag = std.meta.activeTag(element);
    hashAny(&hash, tag);
    switch (element) {
        .cartridge => |value| {
            hashAny(&hash, value.style);
            hashAny(&hash, value.bounds);
            hashAny(&hash, value.platform);
            hashTexture(&hash, value.texture);
            hashTexture(&hash, value.sprite);
            hashAny(&hash, value.selected);
            hashAny(&hash, value.dim);
            hashAny(&hash, value.tilt);
            hashAny(&hash, value.clip_left);
        },
        inline else => |value| hashAny(&hash, value),
    }
    return hash.final();
}

fn hashTexture(hash: *Hasher, optional: ?@import("asset_manifest.zig").Texture) void {
    const value = optional orelse {
        hash.update(&.{0});
        return;
    };
    hash.update(&.{1});
    hashAny(hash, value.width);
    hashAny(hash, value.height);
    hashAny(hash, @intFromPtr(value.pixels.ptr));
    hashAny(hash, value.pixels.len);
    hashAny(hash, value.content_x);
    hashAny(hash, value.content_y);
    hashAny(hash, value.content_width);
    hashAny(hash, value.content_height);
}

fn hashAny(hash: *Hasher, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .bool, .int, .float, .@"enum" => {
            var copy = value;
            hash.update(std.mem.asBytes(&copy));
        },
        .@"struct" => inline for (@typeInfo(T).@"struct".field_names) |field_name| hashAny(hash, @field(value, field_name)),
        .pointer => |pointer| {
            if (pointer.size != .slice) @compileError("unsupported semantic pointer");
            hashAny(hash, value.len);
            hash.update(std.mem.sliceAsBytes(value));
        },
        else => @compileError("unsupported semantic value " ++ @typeName(T)),
    }
}

test "selection change damages the connected focus path" {
    const views = @import("ui.zig");
    var first = views.settings(0, .{}, "Off", "Off");
    var previous = Scene.capture(&first);
    var second = views.settings(1, .{}, "Off", "Off");
    const next = Scene.capture(&second);
    const changed = Scene.changes(&previous, &next);
    try std.testing.expect(!changed.full);
    try std.testing.expect(changed.len > 0);
    var area: usize = 0;
    for (changed.slice()) |rect| area += @as(usize, rect.width) * rect.height;
    try std.testing.expect(area < @as(usize, @import("design.zig").geometry.width) * @import("design.zig").geometry.height);
    previous = Scene.capture(&second);
    try std.testing.expectEqual(@as(usize, 0), Scene.changes(&previous, &next).len);
}

test "inactive pages accumulate damage until used" {
    var tracker = try PageTracker.init(3);
    var first = RectSet{};
    first.add(.{ .x = 10, .y = 10, .width = 20, .height = 20 });
    tracker.invalidate(&first);
    try std.testing.expectEqual(@as(usize, 1), tracker.take(1).len);
    var second = RectSet{};
    second.add(.{ .x = 100, .y = 100, .width = 20, .height = 20 });
    tracker.invalidate(&second);
    try std.testing.expectEqual(@as(usize, 2), tracker.take(2).len);
    try std.testing.expectEqual(@as(usize, 2), tracker.take(0).len);
}

test "scrolling editorial controls remains partial damage" {
    const views = @import("ui.zig");
    var before = views.settings(2, .{}, "On", "Off");
    var after = views.settings(4, .{}, "On", "Off");
    const old = Scene.capture(&before);
    const next = Scene.capture(&after);
    const changed = Scene.changes(&old, &next);
    var area: usize = 0;
    for (changed.slice()) |rect| area += @as(usize, rect.width) * rect.height;
    try std.testing.expect(area > 0 and area < @as(usize, @import("design.zig").geometry.width) * @import("design.zig").geometry.height);
}

test "damage signatures preserve both hashes across buffered update boundaries" {
    var bytes: [1031]u8 = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @truncate(index * 73 + 19);
    for ([_]usize{ 0, 1, 8, 255, 256, 257, 512, bytes.len }) |length| {
        const expected = Signature{
            std.hash.Wyhash.hash(0x6a09e667f3bcc909, bytes[0..length]),
            std.hash.Wyhash.hash(0xbb67ae8584caa73b, bytes[0..length]),
        };
        for ([_]usize{ 1, 7, 16, 255, 256, bytes.len }) |stride| {
            var hash = Hasher{};
            var offset: usize = 0;
            while (offset < length) {
                const end = @min(length, offset + stride);
                hash.update(bytes[offset..end]);
                offset = end;
            }
            try std.testing.expectEqual(expected, hash.final());
        }
    }
}

test "paint bounds clip cartridges outside the viewport without underflow" {
    const outside = paintBounds(.{ .cartridge = .{
        .bounds = .{ .x = 1120, .y = 154, .width = 256, .height = 330 },
        .platform = "gba",
        .texture = null,
        .sprite = null,
    } });
    try std.testing.expectEqual(@as(u16, 0), outside.width);

    const edge = paintBounds(.{ .cartridge = .{
        .bounds = .{ .x = 1000, .y = 154, .width = 256, .height = 330 },
        .platform = "gba",
        .texture = null,
        .sprite = null,
    } });
    try std.testing.expectEqual(@as(u16, 24), edge.width);

    const nudged = paintBounds(.{ .cartridge = .{
        .bounds = .{ .x = 100, .y = 154, .width = 256, .height = 330 },
        .platform = "gba",
        .texture = null,
        .sprite = null,
        .focus_offset_x = -10,
    } });
    try std.testing.expectEqual(@as(u16, 90), nudged.x);
}
