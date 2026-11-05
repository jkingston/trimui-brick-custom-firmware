// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const Setting = enum { brightness, performance, display_timeout, suspend_timeout, appearance };
pub const Performance = enum { battery, balanced, performance };

pub const Values = struct {
    appearance: @import("theme.zig").Mode = .light,
    brightness: u8 = 10,
    performance: Performance = .balanced,
    display_timeout: u8 = 4,
    suspend_timeout: u8 = 0,

    pub fn adjust(self: *Values, setting: Setting, direction: i8) void {
        switch (setting) {
            .appearance => self.appearance = if (self.appearance == .light) .dark else .light,
            .brightness => self.brightness = step(self.brightness, 11, direction),
            .performance => self.performance = @fromBackingInt(@intCast(step(@backingInt(self.performance), 3, direction))),
            .display_timeout => self.display_timeout = step(self.display_timeout, display_seconds.len, direction),
            .suspend_timeout => self.suspend_timeout = step(self.suspend_timeout, suspend_seconds.len, direction),
        }
    }

    pub fn value(self: Values, setting: Setting) []const u8 {
        return switch (setting) {
            .appearance => if (self.appearance == .light) "Light" else "Dark",
            .brightness => brightness_labels[self.brightness],
            .performance => performance_labels[@backingInt(self.performance)],
            .display_timeout => display_labels[self.display_timeout],
            .suspend_timeout => suspend_labels[self.suspend_timeout],
        };
    }
};

pub const display_seconds = [_]u32{ 0, 30, 60, 180, 300, 600 };
pub const suspend_seconds = [_]u32{ 0, 300, 900, 1800, 3600 };
const brightness_labels = [_][]const u8{ "Minimum", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%" };
const performance_labels = [_][]const u8{ "Power saver", "Balanced", "Performance" };
const display_labels = [_][]const u8{ "Never", "30 seconds", "1 minute", "3 minutes", "5 minutes", "10 minutes" };
const suspend_labels = [_][]const u8{ "Never", "5 minutes", "15 minutes", "30 minutes", "1 hour" };

fn step(current: u8, count: usize, direction: i8) u8 {
    if (direction < 0) return if (current == 0) @intCast(count - 1) else current - 1;
    return @intCast((@as(usize, current) + 1) % count);
}

fn readNumber(io: std.Io, path: []const u8, maximum: u32) ?u32 {
    var buffer: [32]u8 = undefined;
    const data = std.Io.Dir.cwd().readFile(io, path, &buffer) catch return null;
    const value = std.fmt.parseInt(u32, std.mem.trim(u8, data, " \t\r\n"), 10) catch return null;
    return if (value <= maximum) value else null;
}

fn readBrightness(io: std.Io) ?u8 {
    var buffer: [32]u8 = undefined;
    const data = std.Io.Dir.cwd().readFile(io, "/data/settings/brightness", &buffer) catch return null;
    const text = std.mem.trim(u8, data, " \t\r\n");
    const number = if (std.mem.startsWith(u8, text, "1 ")) text[2..] else text;
    const value = std.fmt.parseInt(u8, number, 10) catch return null;
    return if (value <= 10) value else null;
}

fn indexOf(comptime values: anytype, value: u32) ?u8 {
    for (values, 0..) |candidate, index| if (candidate == value) return @intCast(index);
    return null;
}

pub fn load(io: std.Io) Values {
    var result = Values{};
    if (readNumber(io, "/data/settings/appearance", 1)) |value| result.appearance = @fromBackingInt(@intCast(value));
    if (readBrightness(io)) |value| result.brightness = value;
    if (readNumber(io, "/data/settings/display-timeout", 86400)) |value|
        result.display_timeout = indexOf(display_seconds, value) orelse result.display_timeout;
    if (readNumber(io, "/data/settings/suspend-timeout", 86400)) |value|
        result.suspend_timeout = indexOf(suspend_seconds, value) orelse result.suspend_timeout;
    var buffer: [32]u8 = undefined;
    const data = std.Io.Dir.cwd().readFile(io, "/data/settings/performance", &buffer) catch return result;
    const profile = std.mem.trim(u8, data, " \t\r\n");
    const info = @typeInfo(Performance).@"enum";
    inline for (info.field_names, info.field_values) |name, value| {
        if (std.mem.eql(u8, profile, name)) result.performance = @fromBackingInt(@intCast(value));
    }
    return result;
}

pub fn apply(io: std.Io, values: Values, setting: Setting) !void {
    if (setting == .appearance) {
        const dir = try std.Io.Dir.cwd().createDirPathOpen(io, "/data/settings", .{});
        defer dir.close(io);
        return saveAppearance(io, dir, values.appearance);
    }
    var number: [16]u8 = undefined;
    const value = switch (setting) {
        .appearance => unreachable,
        .brightness => try std.fmt.bufPrint(&number, "{d}", .{values.brightness}),
        .performance => @tagName(values.performance),
        .display_timeout => try std.fmt.bufPrint(&number, "{d}", .{display_seconds[values.display_timeout]}),
        .suspend_timeout => try std.fmt.bufPrint(&number, "{d}", .{suspend_seconds[values.suspend_timeout]}),
    };
    var child = try std.process.spawn(io, .{ .argv = &.{ "/usr/sbin/brick-settings", @tagName(setting), value } });
    const term = try child.wait(io);
    switch (term) {
        .exited => |status| if (status != 0) return error.SettingApplyFailed,
        else => return error.SettingApplyFailed,
    }
}

test "settings wrap in both directions" {
    var values = Values{};
    values.brightness = 0;
    values.adjust(.brightness, -1);
    try std.testing.expectEqual(@as(u8, 10), values.brightness);
    values.adjust(.brightness, 1);
    try std.testing.expectEqual(@as(u8, 0), values.brightness);
    values.performance = .performance;
    values.adjust(.performance, 1);
    try std.testing.expectEqual(Performance.battery, values.performance);
}

pub fn saveAppearance(io: std.Io, dir: std.Io.Dir, mode: @import("theme.zig").Mode) !void {
    try dir.writeFile(io, .{ .sub_path = "appearance.tmp", .data = if (mode == .light) "0\n" else "1\n" });
    try dir.rename("appearance.tmp", dir, "appearance", io);
}

test "appearance saves atomically without affecting device settings" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var values = Values{};
    values.adjust(.appearance, 1);
    try std.testing.expectEqual(@import("theme.zig").Mode.dark, values.appearance);
    try saveAppearance(std.testing.io, temporary.dir, values.appearance);
    var buffer: [8]u8 = undefined;
    try std.testing.expectEqualStrings("1\n", try temporary.dir.readFile(std.testing.io, "appearance", &buffer));
    values.adjust(.appearance, -1);
    try saveAppearance(std.testing.io, temporary.dir, values.appearance);
    try std.testing.expectEqualStrings("0\n", try temporary.dir.readFile(std.testing.io, "appearance", &buffer));
    try std.testing.expectEqual(@as(u8, 10), values.brightness);
}

pub fn labels(setting: Setting) []const []const u8 {
    return switch (setting) {
        .brightness => &brightness_labels,
        .performance => &performance_labels,
        .display_timeout => &display_labels,
        .suspend_timeout => &suspend_labels,
        .appearance => &.{ "Light", "Dark" },
    };
}

pub fn title(setting: Setting) []const u8 {
    return switch (setting) {
        .brightness => "Brightness",
        .performance => "Performance",
        .display_timeout => "Screen off",
        .suspend_timeout => "Suspend",
        .appearance => "Appearance",
    };
}
