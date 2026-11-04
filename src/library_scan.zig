// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const catalog = @import("catalog.zig");

const Hashes = struct {
    sha256: ?[]const u8 = null,
    sha1: ?[]const u8 = null,
    crc32: ?[]const u8 = null,
    size: ?usize = null,
};

const Entry = struct {
    rom: []const u8,
    platform: []const u8,
    title: []const u8,
    digests: []const Hashes,
};

const Inventory = struct {
    schema_version: u32 = 1,
    games: []const Entry,
};

fn shouldHash(path: []const u8) bool {
    const extension = std.fs.path.extension(path);
    for ([_][]const u8{ ".zip", ".7z", ".chd", ".cue", ".m3u", ".pbp", ".ccd" }) |excluded|
        if (std.ascii.eqlIgnoreCase(extension, excluded)) return false;
    return true;
}

fn digest(allocator: std.mem.Allocator, bytes: []const u8) !Hashes {
    var sha256: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    var sha1: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &sha256, .{});
    std.crypto.hash.Sha1.hash(bytes, &sha1, .{});
    const crc = std.hash.crc.Crc32.hash(bytes);
    return .{
        .sha256 = try std.fmt.allocPrint(allocator, "{x}", .{sha256}),
        .sha1 = try std.fmt.allocPrint(allocator, "{x}", .{sha1}),
        .crc32 = try std.fmt.allocPrint(allocator, "{x:0>8}", .{crc}),
        .size = bytes.len,
    };
}

fn hashes(io: std.Io, allocator: std.mem.Allocator, platform: []const u8, path: []const u8) ![]const Hashes {
    if (!shouldHash(path)) return &.{};
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator,
        .limited(64 * 1024 * 1024)) catch return &.{};
    var variants: std.ArrayList(Hashes) = .empty;
    try variants.append(allocator, try digest(allocator, bytes));
    const extension = std.fs.path.extension(path);
    if (std.mem.eql(u8, platform, "nes") and std.ascii.eqlIgnoreCase(extension, ".nes") and
        bytes.len >= 16 and std.mem.eql(u8, bytes[0..4], "NES\x1a")) {
        const trainer: usize = if (bytes[6] & 0x04 != 0) 512 else 0;
        if (bytes.len > 16 + trainer)
            try variants.append(allocator, try digest(allocator, bytes[16 + trainer ..]));
    } else if (std.mem.eql(u8, platform, "snes") and bytes.len > 512 and bytes.len % 1024 == 512) {
        try variants.append(allocator, try digest(allocator, bytes[512..]));
    }
    return variants.toOwnedSlice(allocator);
}

pub fn inventory(io: std.Io, allocator: std.mem.Allocator, root: []const u8) !Inventory {
    const games = try catalog.discover(io, allocator, root);
    const entries = try allocator.alloc(Entry, games.len);
    for (games, entries) |game, *entry| {
        entry.* = .{
            .rom = try std.fs.path.relativePosix(allocator, "/", root, game.rom_path),
            .platform = game.platform_id,
            .title = game.title,
            .digests = try hashes(io, allocator, game.platform_id, game.rom_path),
        };
    }
    return .{ .games = entries };
}

pub fn write(io: std.Io, allocator: std.mem.Allocator, root: []const u8) !void {
    const result = try inventory(io, allocator, root);
    var buffer: [16 * 1024]u8 = undefined;
    var output = std.Io.File.stdout().writer(io, &buffer);
    try std.json.Stringify.value(result, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}

test "inventory hashes cartridge files and leaves containers for name matching" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.createDirPath(io, "Roms/GB");
    try temporary.dir.createDirPath(io, "Roms/PS");
    try temporary.dir.writeFile(io, .{ .sub_path = "Roms/GB/Tetris.gb", .data = "abc" });
    try temporary.dir.writeFile(io, .{ .sub_path = "Roms/PS/Game.chd", .data = "container" });
    const result = try inventory(io, allocator, root);
    try std.testing.expectEqual(@as(usize, 2), result.games.len);
    const cartridge = if (std.mem.eql(u8, result.games[0].platform, "gb")) result.games[0] else result.games[1];
    const disc = if (std.mem.eql(u8, result.games[0].platform, "psx")) result.games[0] else result.games[1];
    try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", cartridge.digests[0].sha256.?);
    try std.testing.expectEqualStrings("352441c2", cartridge.digests[0].crc32.?);
    try std.testing.expectEqual(@as(usize, 0), disc.digests.len);
}

test "inventory includes raw and headerless NES identities" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.createDirPath(io, "Roms/FC");
    const rom = "NES\x1a" ++ ([_]u8{0} ** 12) ++ "payload";
    try temporary.dir.writeFile(io, .{ .sub_path = "Roms/FC/Game.nes", .data = rom });
    const result = try inventory(io, allocator, root);
    try std.testing.expectEqual(@as(usize, 1), result.games.len);
    try std.testing.expectEqual(@as(usize, 2), result.games[0].digests.len);
    try std.testing.expectEqualStrings("239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5", result.games[0].digests[1].sha256.?);
}
