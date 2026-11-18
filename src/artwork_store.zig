// SPDX-License-Identifier: GPL-2.0-only
//! Firmware-owned artwork snapshot. This schema contains only ROM identity,
//! provider provenance and bounded display derivatives.
const std = @import("std");

const maximum_manifest_bytes = 8 * 1024 * 1024;

pub const State = enum { missing, queued, fetching, ready, failed };

pub const Reference = struct {
    content_id: []const u8,
    path: []const u8,
    source: []const u8,
    width: u16 = 0,
    height: u16 = 0,
};

pub const Texture = struct {
    width: u16,
    height: u16,
    pixels: []const u32,
    content_x: u16,
    content_y: u16,
    content_width: u16,
    content_height: u16,
};

pub const Assets = struct {
    state: State = .missing,
    title: ?[]const u8 = null,
    reference: ?Reference = null,
    // Decoded only for the current process snapshot. The library service writes
    // bounded, device-sized BRTX derivatives; a later renderer cache can replace
    // this field without changing the persistent schema.
    cover: ?Texture = null,
};

const Artwork = struct {
    content_id: []const u8,
    path: []const u8,
    source: []const u8 = "libretro",
    width: u16 = 0,
    height: u16 = 0,
};

const Entry = struct {
    rom: []const u8,
    title: ?[]const u8 = null,
    region: ?[]const u8 = null,
    artwork: ?Artwork = null,
};

const Manifest = struct {
    schema_version: u32,
    revision: u64 = 0,
    games: []const Entry,
};

fn confinedPath(allocator: std.mem.Allocator, root: []const u8, relative: []const u8) ![]const u8 {
    if (std.Io.Dir.path.isAbsolute(relative)) return error.ArtworkPathEscapesRoot;
    const resolved_root = try std.Io.Dir.path.resolve(allocator, &.{root});
    const resolved = try std.Io.Dir.path.resolve(allocator, &.{ resolved_root, relative });
    if (!std.mem.eql(u8, resolved, resolved_root)) {
        if (!std.mem.startsWith(u8, resolved, resolved_root) or
            resolved.len <= resolved_root.len or resolved[resolved_root.len] != std.Io.Dir.path.sep)
            return error.ArtworkPathEscapesRoot;
    }
    return resolved;
}

fn loadTextureFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !Texture {
    const contents = try std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .limited(4 * 1024 * 1024));
    defer std.heap.page_allocator.free(contents);
    if (contents.len < 8 or !std.mem.eql(u8, contents[0..4], "BRTX")) return error.InvalidArtworkTexture;
    const width = @as(u16, contents[4]) | (@as(u16, contents[5]) << 8);
    const height = @as(u16, contents[6]) | (@as(u16, contents[7]) << 8);
    const count = @as(usize, width) * height;
    if (width == 0 or height == 0 or contents.len != 8 + count * 4) return error.InvalidArtworkTexture;
    const pixels = try allocator.alloc(u32, count);
    var min_x = width;
    var min_y = height;
    var max_x: u16 = 0;
    var max_y: u16 = 0;
    for (pixels, 0..) |*pixel, index| {
        const offset = 8 + index * 4;
        pixel.* = @as(u32, contents[offset]) |
            (@as(u32, contents[offset + 1]) << 8) |
            (@as(u32, contents[offset + 2]) << 16) |
            (@as(u32, contents[offset + 3]) << 24);
        if (contents[offset + 3] != 0) {
            const x: u16 = @intCast(index % width);
            const y: u16 = @intCast(index / width);
            min_x = @min(min_x, x);
            min_y = @min(min_y, y);
            max_x = @max(max_x, x);
            max_y = @max(max_y, y);
        }
    }
    const empty = min_x == width;
    return .{
        .width = width,
        .height = height,
        .pixels = pixels,
        .content_x = if (empty) 0 else min_x,
        .content_y = if (empty) 0 else min_y,
        .content_width = if (empty) width else max_x - min_x + 1,
        .content_height = if (empty) height else max_y - min_y + 1,
    };
}

pub fn load(io: std.Io, allocator: std.mem.Allocator, data_root: []const u8) !std.StringHashMap(Assets) {
    var result: std.StringHashMap(Assets) = .init(allocator);
    const library_root = try std.Io.Dir.path.join(allocator, &.{ data_root, "Library" });
    const manifest_path = try std.Io.Dir.path.join(allocator, &.{ library_root, "library-v2.json" });
    const contents = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(maximum_manifest_bytes)) catch |err| switch (err) {
        error.FileNotFound => return result,
        else => return err,
    };
    const manifest = try std.json.parseFromSliceLeaky(Manifest, allocator, contents, .{ .ignore_unknown_fields = false, .allocate = .alloc_always });
    if (manifest.schema_version != 2) return error.UnsupportedArtworkManifest;
    for (manifest.games) |entry| {
        const rom = try confinedPath(allocator, data_root, entry.rom);
        const art = entry.artwork orelse {
            try result.put(rom, .{ .title = entry.title });
            continue;
        };
        const path = try confinedPath(allocator, library_root, art.path);
        const reference = Reference{ .content_id = art.content_id, .path = path, .source = art.source, .width = art.width, .height = art.height };
        const texture = loadTextureFile(io, allocator, path) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        try result.put(rom, .{ .state = if (texture == null) .missing else .ready, .title = entry.title, .reference = reference, .cover = texture });
    }
    return result;
}

test "firmware library snapshot loads a display derivative" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.createDirPath(io, "Library/artwork/rendered");
    try temporary.dir.writeFile(io, .{ .sub_path = "Library/artwork/rendered/test.brtx", .data = "BRTX\x02\x00\x01\x00" ++
        "\x03\x02\x01\xff\x30\x20\x10\x80" });
    try temporary.dir.writeFile(io, .{ .sub_path = "Library/library-v2.json", .data =
        \\{"schema_version":2,"revision":3,"games":[
        \\{"rom":"Roms/GB/Tetris.gb","title":"Tetris","region":"World","artwork":{"content_id":"sha256:test","path":"artwork/rendered/test.brtx","source":"libretro","width":2,"height":1}}
        \\]}
    });
    var assets = try load(io, allocator, root);
    defer assets.deinit();
    const rom = try std.Io.Dir.path.join(allocator, &.{ root, "Roms/GB/Tetris.gb" });
    const mapped = assets.get(rom).?;
    try std.testing.expectEqual(State.ready, mapped.state);
    try std.testing.expectEqualStrings("sha256:test", mapped.reference.?.content_id);
    try std.testing.expectEqualStrings("Tetris", mapped.title.?);
    try std.testing.expectEqual(@as(u16, 2), mapped.cover.?.width);
}

test "artwork paths remain inside the firmware library" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.ArtworkPathEscapesRoot, confinedPath(arena.allocator(), "/data/Library", "../outside.brtx"));
    try std.testing.expectError(error.ArtworkPathEscapesRoot, confinedPath(arena.allocator(), "/data/Library", "/outside.brtx"));
}
