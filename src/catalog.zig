// SPDX-License-Identifier: GPL-2.0-only

const std = @import("std");
const asset_manifest = @import("asset_manifest.zig");

pub const Cover = enum { library, falling, minekart, adjustris, rkanoid, willow };

pub const Game = struct {
    title: []const u8,
    system: []const u8,
    platform_id: []const u8 = "",
    summary: []const u8,
    core_path: []const u8,
    rom_path: []const u8,
    cover: Cover,
    assets: asset_manifest.Assets = .{},
};

pub const games = [_]Game{
    .{
        .title = "FALLING",
        .system = "NINTENDO NES",
        .summary = "ARCADE PLATFORMER",
        .core_path = "/usr/lib/libretro/fceumm_libretro.so",
        .rom_path = "/data/Roms/FC/falling.nes",
        .cover = .falling,
    },
    .{
        .title = "MINEKART MADNESS",
        .system = "NINTENDO NES",
        .summary = "HIGH SPEED RAILS",
        .core_path = "/usr/lib/libretro/fceumm_libretro.so",
        .rom_path = "/data/Roms/FC/minekart-madness.nes",
        .cover = .minekart,
    },
    .{
        .title = "ADJUSTRIS",
        .system = "NINTENDO GAME BOY",
        .summary = "TACTICAL BLOCK PUZZLE",
        .core_path = "/usr/lib/libretro/mgba_libretro.so",
        .rom_path = "/data/Roms/GB/adjustris.gb",
        .cover = .adjustris,
    },
    .{
        .title = "RKANOID",
        .system = "GAME BOY ADVANCE",
        .summary = "TEN LEVEL BREAKOUT",
        .core_path = "/usr/lib/libretro/mgba_libretro.so",
        .rom_path = "/data/Roms/GBA/rkanoid.gba",
        .cover = .rkanoid,
    },
    .{
        .title = "WILLOWS DREAM",
        .system = "SEGA MEGA DRIVE",
        .summary = "DREAMLIKE ADVENTURE",
        .core_path = "/usr/lib/libretro/genesis_plus_gx_libretro.so",
        .rom_path = "/data/Roms/MD/willows-dream.md",
        .cover = .willow,
    },
};

const System = struct {
    id: []const u8,
    aliases: []const u8,
    label: []const u8,
    core: []const u8,
    extensions: []const u8,
};

const systems = [_]System{
    .{ .id = "nes", .aliases = "FC NES", .label = "NINTENDO NES", .core = "fceumm", .extensions = ".nes .unf .unif .zip .7z" },
    .{ .id = "gb", .aliases = "GB", .label = "NINTENDO GAME BOY", .core = "mgba", .extensions = ".gb .zip .7z" },
    .{ .id = "gbc", .aliases = "GBC", .label = "GAME BOY COLOR", .core = "mgba", .extensions = ".gb .gbc .zip .7z" },
    .{ .id = "gba", .aliases = "GBA MGBA", .label = "GAME BOY ADVANCE", .core = "mgba", .extensions = ".gba .zip .7z" },
    .{ .id = "mastersystem", .aliases = "MS SMS MASTERSYSTEM", .label = "SEGA MASTER SYSTEM", .core = "genesis_plus_gx", .extensions = ".sms .zip .7z" },
    .{ .id = "gamegear", .aliases = "GG GAMEGEAR", .label = "SEGA GAME GEAR", .core = "genesis_plus_gx", .extensions = ".gg .zip .7z" },
    .{ .id = "megadrive", .aliases = "MD GENESIS MEGADRIVE", .label = "SEGA MEGA DRIVE", .core = "genesis_plus_gx", .extensions = ".md .gen .bin .smd .zip .7z" },
    .{ .id = "snes", .aliases = "SFC SNES", .label = "SUPER NINTENDO", .core = "snes9x", .extensions = ".sfc .smc .zip .7z" },
    .{ .id = "psx", .aliases = "PS PS1 PSX", .label = "SONY PLAYSTATION", .core = "pcsx_rearmed", .extensions = ".chd .cue .m3u .pbp .ccd" },
    .{ .id = "neogeo", .aliases = "NEOGEO NG", .label = "NEO GEO", .core = "fbneo_neogeo", .extensions = ".zip" },
    .{ .id = "ngpc", .aliases = "NGP NGPC", .label = "NEO GEO POCKET", .core = "mednafen_ngp", .extensions = ".ngp .ngc .zip .7z" },
};

fn contains(list: []const u8, value: []const u8) bool {
    var tokens = std.mem.tokenizeScalar(u8, list, ' ');
    while (tokens.next()) |token| {
        if (std.ascii.eqlIgnoreCase(token, value)) return true;
    }
    return false;
}

fn systemFor(name: []const u8) ?System {
    // Accept MinUI's human-readable folder names with emulator tags too.
    const tag = if (std.mem.findScalarLast(u8, name, '(')) |start|
        if (std.mem.endsWith(u8, name, ")")) name[start + 1 .. name.len - 1] else name
    else
        name;
    for (systems) |system| {
        if (contains(system.aliases, tag)) return system;
    }
    return null;
}

fn hidden(path: []const u8) bool {
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (std.mem.startsWith(u8, part, ".")) return true;
    }
    return false;
}

fn lessThan(_: void, a: Game, b: Game) bool {
    return std.ascii.lessThanIgnoreCase(a.title, b.title);
}

/// Strings and the returned slice belong to allocator (normally a session arena).
/// Enumerate actual root entries once: FAT's case folding must not duplicate ROMs.
pub fn discover(io: std.Io, allocator: std.mem.Allocator, root: []const u8) ![]const Game {
    var found: std.ArrayList(Game) = .empty;
    var data = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer data.close(io);
    var roots = data.iterate();
    while (try roots.next(io)) |entry| {
        if (entry.kind != .directory or !std.ascii.eqlIgnoreCase(entry.name, "roms")) continue;
        const rom_root = try std.Io.Dir.path.join(allocator, &.{ root, entry.name });
        var roms = try data.openDir(io, entry.name, .{ .iterate = true });
        defer roms.close(io);
        var folders = roms.iterate();
        while (try folders.next(io)) |folder| {
            if (folder.kind != .directory) continue;
            const system = systemFor(folder.name) orelse continue;
            const folder_path = try std.Io.Dir.path.join(allocator, &.{ rom_root, folder.name });
            var dir = try roms.openDir(io, folder.name, .{ .iterate = true });
            defer dir.close(io);
            var walker = try dir.walk(allocator);
            defer walker.deinit();
            while (try walker.next(io)) |file| {
                if (hidden(file.path)) {
                    if (file.kind == .directory) walker.leave(io);
                    continue;
                }
                if (file.kind != .file or std.ascii.eqlIgnoreCase(file.basename, "neogeo.zip")) continue;
                if (!contains(system.extensions, std.Io.Dir.path.extension(file.basename))) continue;
                const path = try std.Io.Dir.path.join(allocator, &.{ folder_path, file.path });
                var game = Game{
                    .title = try allocator.dupe(u8, std.Io.Dir.path.stem(file.basename)),
                    .system = system.label,
                    .platform_id = system.id,
                    .summary = system.label,
                    .core_path = try std.fmt.allocPrint(allocator, "/usr/lib/libretro/{s}_libretro.so", .{system.core}),
                    .rom_path = path,
                    .cover = .library,
                };
                for (games) |demo| {
                    if (std.mem.eql(u8, std.Io.Dir.path.basename(demo.rom_path), file.basename)) {
                        game.title = demo.title;
                        game.summary = demo.summary;
                        game.cover = demo.cover;
                        break;
                    }
                }
                try found.append(allocator, game);
            }
        }
    }
    // Playlist members are launched through their playlist, not separate entries.
    var members: std.StringHashMap(void) = .init(allocator);
    for (found.items) |game| {
        if (!std.ascii.eqlIgnoreCase(std.Io.Dir.path.extension(game.rom_path), ".m3u")) continue;
        const contents = std.Io.Dir.cwd().readFileAlloc(io, game.rom_path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => {
                std.log.warn("Cannot read playlist {s}: {s}", .{ game.rom_path, @errorName(err) });
                continue;
            },
        };
        var lines = std.mem.splitScalar(u8, contents, '\n');
        while (lines.next()) |line| {
            const path = std.mem.trim(u8, line, " \t\r\xef\xbb\xbf");
            if (path.len == 0 or path[0] == '#') continue;
            const resolved = try std.Io.Dir.path.resolve(allocator, &.{ std.Io.Dir.path.dirname(game.rom_path).?, path });
            // Do not allow mutually referencing playlists to hide each other.
            if (!std.ascii.eqlIgnoreCase(std.Io.Dir.path.extension(resolved), ".m3u")) try members.put(resolved, {});
        }
    }
    var count: usize = 0;
    for (found.items) |game| {
        if (members.contains(game.rom_path)) continue;
        found.items[count] = game;
        count += 1;
    }
    found.shrinkRetainingCapacity(count);
    var assets = asset_manifest.load(io, allocator, root) catch |err| blk: {
        std.log.warn("Ignoring invalid cartridge asset manifest: {s}", .{@errorName(err)});
        break :blk std.StringHashMap(asset_manifest.Assets).init(allocator);
    };
    defer assets.deinit();
    for (found.items) |*game| {
        if (assets.get(game.rom_path)) |mapping| game.assets = mapping;
    }
    std.mem.sort(Game, found.items, {}, lessThan);
    return found.toOwnedSlice(allocator);
}

test "system aliases include existing and MinUI folder names" {
    for ([_][]const u8{ "FC", "nes", "Nintendo Entertainment System (FC)" }) |alias|
        try std.testing.expectEqualStrings("fceumm", systemFor(alias).?.core);
    try std.testing.expectEqualStrings("mednafen_ngp", systemFor("ngpc").?.core);
    try std.testing.expect(systemFor("BIOS") == null);
}

test "discovery reads mixed layouts and hides BIOS, tracks and playlist members" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    for ([_][]const u8{ "Roms/FC", "roms/snes/Hacks", "ROMS/PS/discs", "Roms/NGP", "Roms/NEOGEO", "Roms/FC/.hidden" }) |path|
        try tmp.dir.createDirPath(io, path);
    for ([_][]const u8{ "Roms/FC/Alpha.NES", "roms/snes/Hacks/Beta.sfc", "ROMS/PS/discs/Disc 1.chd", "ROMS/PS/track.bin", "Roms/NGP/Golf.ngc", "Roms/NEOGEO/neogeo.zip", "Roms/NEOGEO/turfmast.zip", "Roms/FC/.hidden/Ignore.nes", "Roms/FC/cover.png" }) |path|
        try tmp.dir.writeFile(io, .{ .sub_path = path, .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "ROMS/PS/Collection.m3u", .data = "#EXTM3U\r\ndiscs/Disc 1.chd\r\n" });
    const library = try discover(io, allocator, root);
    try std.testing.expectEqual(@as(usize, 5), library.len);
    try std.testing.expectEqualStrings("Alpha", library[0].title);
    try std.testing.expectEqualStrings("Beta", library[1].title);
    try std.testing.expectEqualStrings("Collection", library[2].title);
    try std.testing.expectEqualStrings("Golf", library[3].title);
    try std.testing.expectEqualStrings("turfmast", library[4].title);
    try std.testing.expect(std.mem.endsWith(u8, library[1].rom_path, "/roms/snes/Hacks/Beta.sfc"));
}

test "discovery applies installed artwork metadata without changing launch paths" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    try tmp.dir.createDirPath(io, "Roms/GB");
    try tmp.dir.createDirPath(io, "Assets/Brick");
    try tmp.dir.writeFile(io, .{ .sub_path = "Roms/GB/Tetris.gb", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "Assets/Brick/library.json", .data =
        \\{"schema_version":1,"asset_index_version":"test","games":[
        \\{"rom":"Roms/GB/Tetris.gb","platform":"gb","match":"name","title":"Tetris","model":"gb","surfaces":{"artwork.front":"objects/aa/label.png"}}
        \\],"attribution":{}}
    });
    const library = try discover(io, allocator, root);
    try std.testing.expectEqual(@as(usize, 1), library.len);
    try std.testing.expect(std.mem.endsWith(u8, library[0].assets.model.?, "/Assets/Brick/models/gb.glb"));
    try std.testing.expect(std.mem.endsWith(u8, library[0].assets.front.?, "/Assets/Brick/objects/aa/label.png"));
    try std.testing.expect(std.mem.endsWith(u8, library[0].rom_path, "/Roms/GB/Tetris.gb"));
}
