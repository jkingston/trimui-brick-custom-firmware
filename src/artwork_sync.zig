// SPDX-License-Identifier: GPL-2.0-only
//! Deterministic boundary between the product shell and the background artwork
//! worker. It emits plans and manifests; network and image decoding stay out of
//! the latency-sensitive UI process.
const std = @import("std");
const catalog = @import("catalog.zig");

const Provider = struct { platform: []const u8, collection: []const u8 };
const providers = [_]Provider{
    .{ .platform = "nes", .collection = "Nintendo - Nintendo Entertainment System" },
    .{ .platform = "gb", .collection = "Nintendo - Game Boy" },
    .{ .platform = "gbc", .collection = "Nintendo - Game Boy Color" },
    .{ .platform = "gba", .collection = "Nintendo - Game Boy Advance" },
    .{ .platform = "mastersystem", .collection = "Sega - Master System - Mark III" },
    .{ .platform = "gamegear", .collection = "Sega - Game Gear" },
    .{ .platform = "megadrive", .collection = "Sega - Mega Drive - Genesis" },
    .{ .platform = "snes", .collection = "Nintendo - Super Nintendo Entertainment System" },
    .{ .platform = "psx", .collection = "Sony - PlayStation" },
    .{ .platform = "neogeo", .collection = "SNK - Neo Geo" },
    .{ .platform = "ngpc", .collection = "SNK - Neo Geo Pocket Color" },
};

fn providerFor(platform: []const u8) ?[]const u8 {
    for (providers) |provider| if (std.mem.eql(u8, platform, provider.platform)) return provider.collection;
    return null;
}

pub fn identifier(buffer: *[32]u8, rom_path: []const u8) []const u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(rom_path, &digest, .{});
    return std.fmt.bufPrint(buffer, "{x}", .{digest[0..16]}) catch @panic("artwork id buffer is incorrectly sized");
}

fn safeThumbnailName(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    const result = try allocator.dupe(u8, value);
    for (result) |*byte| switch (byte.*) {
        '&', '*', '/', ':', '`', '<', '>', '?', '\\', '|', '"' => byte.* = '_',
        else => {},
    };
    return result;
}

fn encodePathSegment(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    const alphabet = "0123456789ABCDEF";
    for (value) |byte| {
        const plain = std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~';
        if (plain) try result.append(allocator, byte) else try result.appendSlice(allocator, &.{ '%', alphabet[byte >> 4], alphabet[byte & 15] });
    }
    return result.toOwnedSlice(allocator);
}

fn sourceName(path: []const u8) []const u8 {
    return std.Io.Dir.path.stem(std.Io.Dir.path.basename(path));
}

fn url(allocator: std.mem.Allocator, collection: []const u8, title: []const u8) ![]const u8 {
    const collection_segment = try encodePathSegment(allocator, collection);
    const safe = try safeThumbnailName(allocator, title);
    const title_segment = try encodePathSegment(allocator, safe);
    return std.fmt.allocPrint(allocator, "https://thumbnails.libretro.com/{s}/Named_Boxarts/{s}.png", .{ collection_segment, title_segment });
}

fn overrideTitle(io: std.Io, allocator: std.mem.Allocator, root: []const u8, id: []const u8) !?[]const u8 {
    const path = try std.fmt.allocPrint(allocator, "{s}/Library/overrides/{s}.title", .{ root, id });
    const contents = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(96)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    const title = std.mem.trim(u8, contents, " \t\r\n");
    return if (title.len == 0) null else title;
}

/// TSV is intentional: URLs are encoded, ids have no whitespace and ROM paths
/// may contain spaces. Tabs and newlines in filenames are skipped.
pub fn writePlan(io: std.Io, allocator: std.mem.Allocator, root: []const u8) !void {
    const games = try catalog.discoverBare(io, allocator, root);
    var buffer: [16 * 1024]u8 = undefined;
    var output = std.Io.File.stdout().writer(io, &buffer);
    for (games) |game| {
        if (std.mem.indexOfAny(u8, game.rom_path, "\t\n\r") != null) continue;
        const collection = providerFor(game.platform_id) orelse continue;
        var id_buffer: [32]u8 = undefined;
        const id = identifier(&id_buffer, game.rom_path);
        const corrected = try overrideTitle(io, allocator, root, id);
        const title = corrected orelse game.title;
        const original = try url(allocator, collection, sourceName(game.rom_path));
        const by_title = try url(allocator, collection, title);
        const primary = if (corrected != null) by_title else original;
        const fallback = if (corrected != null) original else by_title;
        const extension = std.Io.Dir.path.extension(game.rom_path);
        const sidecar = try std.fmt.allocPrint(allocator, "{s}.png", .{game.rom_path[0 .. game.rom_path.len - extension.len]});
        try output.interface.print("{s}\t{s}\t{s}\t{s}\t{s}\n", .{ id, game.rom_path, sidecar, primary, fallback });
    }
    try output.interface.flush();
}

const Artwork = struct { content_id: []const u8, path: []const u8, source: []const u8 };
const Entry = struct { rom: []const u8, title: []const u8, artwork: ?Artwork };
const Manifest = struct { schema_version: u32 = 2, revision: i64, games: []const Entry };

pub fn writeManifest(io: std.Io, allocator: std.mem.Allocator, root: []const u8) !void {
    const games = try catalog.discoverBare(io, allocator, root);
    const entries = try allocator.alloc(Entry, games.len);
    for (games, entries) |game, *entry| {
        var id_buffer: [32]u8 = undefined;
        const id = try allocator.dupe(u8, identifier(&id_buffer, game.rom_path));
        const title = try overrideTitle(io, allocator, root, id) orelse game.title;
        const relative_rom = try std.Io.Dir.path.relativePosix(allocator, "/", root, game.rom_path);
        const relative_art = try std.fmt.allocPrint(allocator, "artwork/rendered/{s}.brtx", .{id});
        const absolute_art = try std.Io.Dir.path.join(allocator, &.{ root, "Library", relative_art });
        const present = blk: {
            std.Io.Dir.cwd().access(io, absolute_art, .{}) catch break :blk false;
            break :blk true;
        };
        const source = if (present) blk: {
            const source_path = try std.fmt.allocPrint(allocator, "{s}.source", .{absolute_art[0 .. absolute_art.len - ".brtx".len]});
            const value = std.Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(32)) catch break :blk "libretro";
            break :blk std.mem.trim(u8, value, " \t\r\n");
        } else "libretro";
        entry.* = .{ .rom = relative_rom, .title = title, .artwork = if (present) .{ .content_id = id, .path = relative_art, .source = source } else null };
    }
    const result = Manifest{ .revision = std.Io.Timestamp.now(io, .real).toMilliseconds(), .games = entries };
    var buffer: [16 * 1024]u8 = undefined;
    var output = std.Io.File.stdout().writer(io, &buffer);
    try std.json.Stringify.value(result, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}

pub fn queue(io: std.Io, allocator: std.mem.Allocator, root: []const u8, command: []const u8, rom_path: ?[]const u8, value: []const u8) !void {
    const requests = try std.Io.Dir.path.join(allocator, &.{ root, "Library", "requests" });
    try std.Io.Dir.cwd().createDirPath(io, requests);
    const name = if (rom_path) |rom| blk: {
        var id_buffer: [32]u8 = undefined;
        break :blk try std.fmt.allocPrint(allocator, "{s}.{s}", .{ identifier(&id_buffer, rom), command });
    } else try allocator.dupe(u8, command);
    const path = try std.Io.Dir.path.join(allocator, &.{ requests, name });
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, rom_path orelse "");
    if (value.len != 0) {
        try file.writeStreamingAll(io, "\n");
        try file.writeStreamingAll(io, value);
    }
}

test "provider URLs preserve identity while encoding path syntax" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const value = try url(arena.allocator(), "Nintendo - Game Boy", "Q*bert & Co.");
    try std.testing.expectEqualStrings("https://thumbnails.libretro.com/Nintendo%20-%20Game%20Boy/Named_Boxarts/Q_bert%20_%20Co..png", value);
}

test "content ids are stable and path-specific" {
    var first: [32]u8 = undefined;
    var again: [32]u8 = undefined;
    var other: [32]u8 = undefined;
    try std.testing.expectEqualStrings(identifier(&first, "/data/Roms/GB/Tetris.gb"), identifier(&again, "/data/Roms/GB/Tetris.gb"));
    try std.testing.expect(!std.mem.eql(u8, identifier(&first, "/data/Roms/GB/Tetris.gb"), identifier(&other, "/data/Roms/GBC/Tetris.gb")));
}

test "per-game actions become bounded worker requests" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(io, ".", arena.allocator());
    const rom = try std.Io.Dir.path.join(arena.allocator(), &.{ root, "Roms/GB/Tetris.gb" });
    try queue(io, arena.allocator(), root, "refresh_game", rom, "");
    var id_buffer: [32]u8 = undefined;
    const request = try std.fmt.allocPrint(arena.allocator(), "Library/requests/{s}.refresh_game", .{identifier(&id_buffer, rom)});
    const contents = try temporary.dir.readFileAlloc(io, request, arena.allocator(), .limited(4096));
    try std.testing.expectEqualStrings(rom, contents);
}

test "title overrides are bounded and remain outside the ROM tree" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(io, ".", arena.allocator());
    try temporary.dir.createDirPath(io, "Library/overrides");
    try temporary.dir.writeFile(io, .{ .sub_path = "Library/overrides/identity.title", .data = "  Correct title\n" });
    try std.testing.expectEqualStrings("Correct title", (try overrideTitle(io, arena.allocator(), root, "identity")).?);
}
