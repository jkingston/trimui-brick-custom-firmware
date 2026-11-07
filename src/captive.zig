// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const State = enum { unavailable, connected, no_internet, sign_in_required, signing_in, sign_in_failed };
pub const Command = enum { sign_in, retry, cancel };

pub const Qr = struct {
    cells: [177 * 177]u8 = @splat(0),
    width: u16 = 0,

    pub fn cell(self: *const Qr, x: usize, y: usize) bool {
        return self.width != 0 and self.cells[y * self.width + x] != 0;
    }
};

pub const Snapshot = struct {
    generation: u32 = 0,
    state: State = .unavailable,
    url_bytes: [2048]u8 = @splat(0),
    url_len: usize = 0,
    qr: Qr = .{},

    pub fn url(self: *const Snapshot) []const u8 {
        return self.url_bytes[0..self.url_len];
    }

    pub fn summary(self: Snapshot) []const u8 {
        return switch (self.state) {
            .unavailable => "Unavailable",
            .connected => "Connected",
            .no_internet => "No internet",
            .sign_in_required => "Sign-in required",
            .signing_in => "Signing in…",
            .sign_in_failed => "Sign-in failed",
        };
    }

    pub fn primary(self: Snapshot) []const u8 {
        return switch (self.state) {
            .sign_in_required => "Sign in",
            .signing_in => "Cancel",
            .sign_in_failed, .no_internet => "Retry",
            else => "Check status",
        };
    }

    pub fn command(self: Snapshot) ?Command {
        return switch (self.state) {
            .sign_in_required => .sign_in,
            .signing_in => .cancel,
            .sign_in_failed, .no_internet => .retry,
            else => null,
        };
    }
};

fn copyUrl(snapshot: *Snapshot, value: []const u8) void {
    if (value.len == 0 or value.len > snapshot.url_bytes.len) return;
    @memcpy(snapshot.url_bytes[0..value.len], value);
    snapshot.url_len = value.len;
}

pub fn parse(text: []const u8) Snapshot {
    var snapshot = Snapshot{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const split = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = line[0..split];
        const value = line[split + 1 ..];
        if (std.mem.eql(u8, key, "generation")) snapshot.generation = std.fmt.parseInt(u32, value, 10) catch 0;
        if (std.mem.eql(u8, key, "portal_url")) copyUrl(&snapshot, value);
        if (std.mem.eql(u8, key, "ux_state")) {
            snapshot.state = if (std.mem.eql(u8, value, "connected")) .connected else if (std.mem.eql(u8, value, "no-internet")) .no_internet else if (std.mem.eql(u8, value, "sign-in-required")) .sign_in_required else if (std.mem.eql(u8, value, "signing-in")) .signing_in else if (std.mem.eql(u8, value, "sign-in-failed")) .sign_in_failed else .unavailable;
        }
    }
    return snapshot;
}

pub fn status(io: std.Io) Snapshot {
    const result = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "/usr/bin/brick-captive-control", "status" },
        .stdout_limit = .limited(8192),
        .stderr_limit = .limited(1024),
    }) catch return .{};
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);
    return switch (result.term) {
        .exited => |code| if (code == 0) parse(result.stdout) else .{},
        else => .{},
    };
}

pub fn execute(io: std.Io, command: Command, generation: u32) !void {
    var number: [16]u8 = undefined;
    const value = try std.fmt.bufPrint(&number, "{d}", .{generation});
    const name = switch (command) {
        .sign_in => "sign-in",
        .retry => "retry",
        .cancel => "cancel",
    };
    var child = try std.process.spawn(io, .{ .argv = &.{ "/usr/bin/brick-captive-control", name, value }, .stdout = .ignore, .stderr = .ignore });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| {
            if (code == 3) return error.StaleGeneration;
            if (code != 0) return error.ControlFailed;
        },
        else => return error.ControlFailed,
    }
}

fn quoted(line: []const u8) ?[]const u8 {
    const first = std.mem.indexOfScalar(u8, line, '"') orelse return null;
    const rest = line[first + 1 ..];
    const last = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..last];
}

pub fn parseXpm(data: []const u8) !Qr {
    var lines = std.mem.splitScalar(u8, data, '\n');
    var width: u16 = 0;
    var colors: usize = 0;
    while (lines.next()) |line| {
        const value = quoted(line) orelse continue;
        var fields = std.mem.tokenizeScalar(u8, value, ' ');
        width = std.fmt.parseInt(u16, fields.next() orelse continue, 10) catch continue;
        const height = std.fmt.parseInt(u16, fields.next() orelse return error.InvalidQr, 10) catch return error.InvalidQr;
        colors = std.fmt.parseInt(usize, fields.next() orelse return error.InvalidQr, 10) catch return error.InvalidQr;
        const chars = std.fmt.parseInt(usize, fields.next() orelse return error.InvalidQr, 10) catch return error.InvalidQr;
        if (width == 0 or width != height or width > 177 or colors == 0 or colors > 8 or chars != 1) return error.InvalidQr;
        break;
    }
    if (width == 0) return error.InvalidQr;
    var dark: ?u8 = null;
    for (0..colors) |_| {
        const value = quoted(lines.next() orelse return error.InvalidQr) orelse return error.InvalidQr;
        if (std.mem.indexOf(u8, value, "#000000") != null or std.mem.indexOf(u8, value, "black") != null) dark = value[0];
    }
    const marker = dark orelse return error.InvalidQr;
    var result = Qr{ .width = width };
    for (0..width) |y| {
        const value = quoted(lines.next() orelse return error.InvalidQr) orelse return error.InvalidQr;
        if (value.len != width) return error.InvalidQr;
        for (value, 0..) |cell, x| result.cells[y * width + x] = @intFromBool(cell == marker);
    }
    return result;
}

pub fn ensureQr(io: std.Io, snapshot: *Snapshot) void {
    if (snapshot.qr.width != 0 or snapshot.url_len == 0) return;
    const result = std.process.run(std.heap.page_allocator, io, .{
        .argv = &.{ "/usr/bin/qrencode", "-t", "XPM", "-s", "1", "-m", "4", "-o", "-", "--", snapshot.url() },
        .stdout_limit = .limited(131072),
        .stderr_limit = .limited(1024),
    }) catch return;
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| {
            if (code == 0) snapshot.qr = parseXpm(result.stdout) catch .{};
        },
        else => {},
    }
}

test "status parser exposes stable product actions" {
    const required = parse("generation=7\nux_state=sign-in-required\nportal_url=https://portal.test/login\n");
    try std.testing.expectEqual(@as(u32, 7), required.generation);
    try std.testing.expectEqual(State.sign_in_required, required.state);
    try std.testing.expectEqualStrings("Sign in", required.primary());
    try std.testing.expectEqualStrings("https://portal.test/login", required.url());
}

test "XPM parser rejects malformed data and preserves modules" {
    const qr = try parseXpm("/* XPM */\nstatic char *q[] = {\n\"3 3 2 1\",\n\"  c #FFFFFF\",\n\"# c #000000\",\n\"# #\",\n\" # \",\n\"# #\"};\n");
    try std.testing.expect(qr.cell(0, 0));
    try std.testing.expect(qr.cell(1, 1));
    try std.testing.expect(!qr.cell(1, 0));
    try std.testing.expectError(error.InvalidQr, parseXpm("\"2 3 2 1\"\n"));
}
