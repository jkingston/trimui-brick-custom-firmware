// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const catalog = @import("catalog.zig");

pub const executable = "/usr/bin/retroarch";
pub const config_path = "/etc/retroarch/retroarch.cfg";

pub fn arguments(game: *const catalog.Game) [6][]const u8 {
    return .{ executable, "--config", config_path, "-L", game.core_path, game.rom_path };
}

pub const Failure = enum {
    missing_core,
    missing_content,
    missing_bios,
    save_storage,
    legacy_conflict,
    emulator,

    pub fn message(self: Failure) []const u8 {
        return switch (self) {
            .missing_core => "EMULATOR NOT INSTALLED",
            .missing_content => "GAME FILE UNAVAILABLE",
            .missing_bios => "ADD NEOGEO.ZIP TO BIOS",
            .save_storage => "SAVE STORAGE UNAVAILABLE",
            .legacy_conflict => "LEGACY SAVES NEED REVIEW",
            .emulator => "GAME FAILED - SEE LAST LOG",
        };
    }

    pub fn fromError(err: anyerror) Failure {
        return switch (err) {
            error.CoreUnavailable => .missing_core,
            error.ContentUnavailable => .missing_content,
            error.BiosUnavailable => .missing_bios,
            error.LegacySaveConflict => .legacy_conflict,
            error.SaveStorageUnavailable => .save_storage,
            else => .emulator,
        };
    }
};

pub const Session = struct { config: []const u8, log: []const u8, saves: []const u8, states: []const u8 };

fn performance(io: std.Io, mode: []const u8) !void {
    var child = try std.process.spawn(io, .{ .argv = &.{ "/usr/sbin/brick-performance", mode } });
    const term = try child.wait(io);
    switch (term) {
        .exited => |status| if (status != 0) return error.PerformancePolicyFailed,
        else => return error.PerformancePolicyFailed,
    }
}

/// Path identity is portable across mounts, but intentionally changes on rename.
/// Do not hash only the basename: distinct folders may contain different games.
pub fn identity(allocator: std.mem.Allocator, game: *const catalog.Game, root: []const u8) ![64]u8 {
    const absolute = try std.Io.Dir.path.resolve(allocator, &.{game.rom_path});
    const base = try std.Io.Dir.path.resolve(allocator, &.{root});
    const relative = try std.Io.Dir.path.relative(allocator, "/", null, base, absolute);
    if (std.Io.Dir.path.isAbsolute(relative) or std.mem.eql(u8, relative, "..") or std.mem.startsWith(u8, relative, "../"))
        return error.ContentUnavailable;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("brick-save-path-v1\x00");
    hash.update(relative);
    return std.fmt.bytesToHex(hash.finalResult(), .lower);
}

fn coreName(game: *const catalog.Game) []const u8 {
    const name = std.Io.Dir.path.basename(game.core_path);
    if (std.mem.eql(u8, name, "mgba_libretro.so")) return "mGBA";
    if (std.mem.eql(u8, name, "fceumm_libretro.so")) return "FCEUmm";
    if (std.mem.eql(u8, name, "genesis_plus_gx_libretro.so")) return "Genesis Plus GX";
    if (std.mem.eql(u8, name, "snes9x_libretro.so")) return "Snes9x";
    if (std.mem.eql(u8, name, "pcsx_rearmed_libretro.so")) return "PCSX-ReARMed";
    if (std.mem.eql(u8, name, "mednafen_ngp_libretro.so")) return "Beetle NeoPop";
    if (std.mem.eql(u8, name, "fbneo_neogeo_libretro.so")) return "FinalBurn Neo (neogeo subset)";
    return std.Io.Dir.path.stem(name);
}

fn migrate(io: std.Io, allocator: std.mem.Allocator, game: *const catalog.Game, library: []const catalog.Game, root: []const u8, session: Session) !void {
    const stem = std.Io.Dir.path.stem(std.Io.Dir.path.basename(game.rom_path));
    var matches: usize = 0;
    var all_matches: usize = 0;
    for (library) |other| {
        if (std.mem.eql(u8, std.Io.Dir.path.stem(std.Io.Dir.path.basename(other.rom_path)), stem)) {
            all_matches += 1;
            if (std.mem.eql(u8, other.core_path, game.core_path)) matches += 1;
        }
    }
    const cwd = std.Io.Dir.cwd();
    // Old files remain intact. Never replace an existing destination.
    for ([_][]const u8{ "Saves", "saves" }) |legacy_root| {
        for ([_][]const u8{ "sram", "states" }, [_][]const u8{ session.saves, session.states }) |kind, destination| {
            const base = try std.Io.Dir.path.join(allocator, &.{ root, legacy_root, kind });
            for ([_][]const u8{ base, try std.Io.Dir.path.join(allocator, &.{ base, coreName(game) }) }) |old_path| {
                var dir = cwd.openDir(io, old_path, .{ .iterate = true }) catch |err| switch (err) {
                    error.FileNotFound => continue,
                    else => return err,
                };
                defer dir.close(io);
                var iterator = dir.iterate();
                while (try iterator.next(io)) |entry| {
                    if (entry.kind != .file or !std.mem.startsWith(u8, entry.name, stem)) continue;
                    const suffix = entry.name[stem.len..];
                    const relevant = if (std.mem.eql(u8, kind, "sram"))
                        std.mem.eql(u8, suffix, ".srm") or std.mem.eql(u8, suffix, ".rtc")
                    else
                        std.mem.startsWith(u8, suffix, ".state");
                    if (!relevant) continue;
                    const candidates = if (std.mem.eql(u8, old_path, base)) all_matches else matches;
                    if (candidates != 1) return error.LegacySaveConflict;
                    const target_dir = try std.Io.Dir.path.join(allocator, &.{ destination, coreName(game) });
                    try cwd.createDirPath(io, target_dir);
                    const target = try std.Io.Dir.path.join(allocator, &.{ target_dir, entry.name });
                    dir.copyFile(entry.name, cwd, target, io, .{ .replace = false }) catch |err| switch (err) {
                        error.PathAlreadyExists => {
                            const old = try dir.readFileAlloc(io, entry.name, allocator, .limited(32 * 1024 * 1024));
                            const current = try cwd.readFileAlloc(io, target, allocator, .limited(32 * 1024 * 1024));
                            if (!std.mem.eql(u8, old, current)) return error.LegacySaveConflict;
                        },
                        else => return err,
                    };
                }
            }
        }
    }
}

pub fn prepare(io: std.Io, allocator: std.mem.Allocator, game: *const catalog.Game, library: []const catalog.Game, root: []const u8, runtime: []const u8) !Session {
    const cwd = std.Io.Dir.cwd();
    const content = cwd.openFile(io, game.rom_path, .{}) catch return error.ContentUnavailable;
    defer content.close(io);
    const stat = content.stat(io) catch return error.ContentUnavailable;
    if (stat.kind != .file or stat.size == 0) return error.ContentUnavailable;
    const core = cwd.openFile(io, game.core_path, .{}) catch return error.CoreUnavailable;
    defer core.close(io);
    const core_stat = core.stat(io) catch return error.CoreUnavailable;
    if (core_stat.kind != .file or core_stat.size == 0) return error.CoreUnavailable;
    // This image uses a separate Neo Geo BIOS archive, matching its SD layout.
    // Presence is checked here; FBNeo validates the archive contents when loading.
    if (std.mem.eql(u8, std.Io.Dir.path.basename(game.core_path), "fbneo_neogeo_libretro.so")) {
        var found = false;
        for ([_][]const u8{
            try std.Io.Dir.path.join(allocator, &.{ root, "BIOS/fbneo/patched/neogeo.zip" }),
            try std.Io.Dir.path.join(allocator, &.{ std.Io.Dir.path.dirname(game.rom_path).?, "neogeo.zip" }),
            try std.Io.Dir.path.join(allocator, &.{ root, "BIOS/fbneo/neogeo.zip" }),
            try std.Io.Dir.path.join(allocator, &.{ root, "BIOS/neogeo.zip" }),
        }) |path| {
            const bios = cwd.openFile(io, path, .{}) catch continue;
            defer bios.close(io);
            const bios_stat = bios.stat(io) catch continue;
            if (bios_stat.kind == .file and bios_stat.size > 0) {
                found = true;
                break;
            }
        }
        if (!found) return error.BiosUnavailable;
    }
    const id = try identity(allocator, game, root);
    const base = try std.Io.Dir.path.join(allocator, &.{ root, "Saves/games", &id });
    const session = Session{
        .config = try std.Io.Dir.path.join(allocator, &.{ runtime, "game.cfg" }),
        .log = try std.Io.Dir.path.join(allocator, &.{ runtime, "last-game.log" }),
        .saves = try std.Io.Dir.path.join(allocator, &.{ base, "sram" }),
        .states = try std.Io.Dir.path.join(allocator, &.{ base, "states" }),
    };
    for ([_][]const u8{ session.saves, session.states, runtime }) |directory|
        cwd.createDirPath(io, directory) catch return error.SaveStorageUnavailable;
    for ([_][]const u8{ session.saves, session.states }) |directory| {
        const core_dir = try std.Io.Dir.path.join(allocator, &.{ directory, coreName(game) });
        cwd.createDirPath(io, core_dir) catch return error.SaveStorageUnavailable;
        const probe = try std.Io.Dir.path.join(allocator, &.{ core_dir, ".write-check" });
        const file = cwd.createFile(io, probe, .{}) catch return error.SaveStorageUnavailable;
        file.close(io);
        cwd.deleteFile(io, probe) catch return error.SaveStorageUnavailable;
    }
    const marker = try std.Io.Dir.path.join(allocator, &.{ base, "content-path.txt" });
    const imported = blk: {
        cwd.access(io, marker, .{}) catch |err| switch (err) {
            error.FileNotFound => break :blk false,
            else => return error.SaveStorageUnavailable,
        };
        break :blk true;
    };
    if (!imported) migrate(io, allocator, game, library, root, session) catch |err| switch (err) {
        error.LegacySaveConflict => return err,
        else => return error.SaveStorageUnavailable,
    };
    // Exercise writes before handing the display to the emulator.
    cwd.writeFile(io, .{ .sub_path = marker, .data = game.rom_path }) catch return error.SaveStorageUnavailable;
    const text = try std.fmt.allocPrint(allocator, "savefile_directory = \"{s}\"\nsavestate_directory = \"{s}\"\n" ++
        "sort_savefiles_enable = \"true\"\nsort_savestates_enable = \"true\"\n" ++
        "sort_savefiles_by_content_enable = \"false\"\nsort_savestates_by_content_enable = \"false\"\n" ++
        "savefiles_in_content_dir = \"false\"\nsavestates_in_content_dir = \"false\"\n" ++
        "savestate_auto_save = \"true\"\nsavestate_auto_load = \"true\"\nautosave_interval = \"10\"\n" ++
        "config_save_on_exit = \"false\"\n", .{ session.saves, session.states });
    cwd.writeFile(io, .{ .sub_path = session.config, .data = text }) catch return error.SaveStorageUnavailable;
    return session;
}

pub fn launch(io: std.Io, game: *const catalog.Game, library: []const catalog.Game) !std.process.Child.Term {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const session = try prepare(io, arena.allocator(), game, library, "/data", "/run/brick-shell");
    const log = try std.Io.Dir.cwd().createFile(io, session.log, .{});
    defer log.close(io);
    try performance(io, "game");
    defer performance(io, "menu") catch |err|
        std.log.err("Failed to restore the menu performance profile: {s}", .{@errorName(err)});
    const argv = arguments(game) ++ [_][]const u8{ "--verbose", "--appendconfig", session.config };
    var child = try std.process.spawn(io, .{ .argv = &argv, .stdout = .{ .file = log }, .stderr = .{ .file = log } });
    return child.wait(io);
}

fn statePath(allocator: std.mem.Allocator, game: *const catalog.Game, session: Session, suffix: []const u8) ![]const u8 {
    return std.Io.Dir.path.join(allocator, &.{
        session.states,
        coreName(game),
        try std.fmt.allocPrint(allocator, "{s}.state{s}", .{ std.Io.Dir.path.stem(std.Io.Dir.path.basename(game.rom_path)), suffix }),
    });
}

pub fn availableStates(io: std.Io, game: *const catalog.Game) [4]bool {
    var result: [4]bool = @splat(false);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const id = identity(allocator, game, "/data") catch return result;
    for (0..4) |slot| {
        const suffix = if (slot == 3) ".auto" else std.fmt.allocPrint(allocator, ".brick-{d}", .{slot + 1}) catch continue;
        const filename = std.fmt.allocPrint(allocator, "{s}.state{s}", .{ std.Io.Dir.path.stem(std.Io.Dir.path.basename(game.rom_path)), suffix }) catch continue;
        const path = std.Io.Dir.path.join(allocator, &.{ "/data/Saves/games", &id, "states", coreName(game), filename }) catch continue;
        const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch continue;
        defer file.close(io);
        const stat = file.stat(io) catch continue;
        result[slot] = stat.kind == .file and stat.size != 0;
    }
    return result;
}

pub fn saveState(io: std.Io, game: *const catalog.Game, library: []const catalog.Game, slot: usize) !void {
    if (slot >= 3) return error.InvalidStateSlot;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const session = try prepare(io, allocator, game, library, "/data", "/run/brick-shell");
    const automatic = try statePath(allocator, game, session, ".auto");
    const manual = try statePath(allocator, game, session, try std.fmt.allocPrint(allocator, ".brick-{d}", .{slot + 1}));
    try std.Io.Dir.cwd().copyFile(automatic, std.Io.Dir.cwd(), manual, io, .{ .replace = true });
}

pub fn loadState(io: std.Io, game: *const catalog.Game, library: []const catalog.Game, slot: usize) !void {
    if (slot > 3) return error.InvalidStateSlot;
    if (slot == 3) {
        if (!availableStates(io, game)[3]) return error.FileNotFound;
        return;
    }
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const session = try prepare(io, allocator, game, library, "/data", "/run/brick-shell");
    const automatic = try statePath(allocator, game, session, ".auto");
    const manual = try statePath(allocator, game, session, try std.fmt.allocPrint(allocator, ".brick-{d}", .{slot + 1}));
    try std.Io.Dir.cwd().copyFile(manual, std.Io.Dir.cwd(), automatic, io, .{ .replace = true });
}

test "launch contract uses an explicit core, config and content path" {
    const argv = arguments(&catalog.games[0]);
    try std.testing.expectEqualStrings(executable, argv[0]);
    try std.testing.expectEqualStrings("--config", argv[1]);
    try std.testing.expectEqualStrings(config_path, argv[2]);
    try std.testing.expectEqualStrings("-L", argv[3]);
    try std.testing.expectEqualStrings("/usr/lib/libretro/fceumm_libretro.so", argv[4]);
    try std.testing.expectEqualStrings("/data/Roms/FC/falling.nes", argv[5]);
}

test "save identity separates folders and survives mount changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var a = catalog.games[0];
    var b = a;
    a.rom_path = "/data/Roms/FC/a/game.nes";
    b.rom_path = "/data/Roms/FC/b/game.nes";
    const first = try identity(arena.allocator(), &a, "/data");
    try std.testing.expect(!std.mem.eql(u8, &first, &(try identity(arena.allocator(), &b, "/data"))));
    a.rom_path = "/media/card/Roms/FC/a/game.nes";
    try std.testing.expectEqualStrings(&first, &(try identity(arena.allocator(), &a, "/media/card")));
    a.rom_path = "/other/game.nes";
    try std.testing.expectError(error.ContentUnavailable, identity(arena.allocator(), &a, "/data"));
}

test "session imports unique legacy saves once and refuses ambiguous progress" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    const runtime = try std.Io.Dir.path.join(allocator, &.{ root, "run" });
    try tmp.dir.createDirPath(io, "Roms/FC/a");
    try tmp.dir.createDirPath(io, "Roms/FC/b");
    try tmp.dir.createDirPath(io, "saves/sram/FCEUmm");
    try tmp.dir.writeFile(io, .{ .sub_path = "Roms/FC/a/game.nes", .data = "rom" });
    try tmp.dir.writeFile(io, .{ .sub_path = "Roms/FC/b/game.nes", .data = "other" });
    try tmp.dir.writeFile(io, .{ .sub_path = "fceumm_libretro.so", .data = "core" });
    try tmp.dir.writeFile(io, .{ .sub_path = "saves/sram/FCEUmm/game.srm", .data = "progress" });
    var a = catalog.games[0];
    a.rom_path = try std.Io.Dir.path.join(allocator, &.{ root, "Roms/FC/a/game.nes" });
    a.core_path = try std.Io.Dir.path.join(allocator, &.{ root, "fceumm_libretro.so" });
    var b = a;
    b.rom_path = try std.Io.Dir.path.join(allocator, &.{ root, "Roms/FC/b/game.nes" });
    try std.testing.expectError(error.LegacySaveConflict, prepare(io, allocator, &a, &.{ a, b }, root, runtime));
    const session = try prepare(io, allocator, &a, &.{a}, root, runtime);
    const save = try std.Io.Dir.path.join(allocator, &.{ session.saves, "FCEUmm/game.srm" });
    const cwd = std.Io.Dir.cwd();
    try std.testing.expectEqualStrings("progress", try cwd.readFileAlloc(io, save, allocator, .limited(100)));
    try cwd.writeFile(io, .{ .sub_path = save, .data = "new progress" });
    _ = try prepare(io, allocator, &a, &.{a}, root, runtime);
    try std.testing.expectEqualStrings("new progress", try cwd.readFileAlloc(io, save, allocator, .limited(100)));
    try std.testing.expectEqualStrings("progress", try tmp.dir.readFileAlloc(io, "saves/sram/FCEUmm/game.srm", allocator, .limited(100)));
    try tmp.dir.writeFile(io, .{ .sub_path = "blocked", .data = "not a directory" });
    try std.testing.expectError(error.SaveStorageUnavailable, prepare(io, allocator, &a, &.{a}, root, try std.Io.Dir.path.join(allocator, &.{ root, "blocked" })));
    // A failed preflight must never spawn an emulator or silently create new saves.
    b.core_path = "/missing-brick-test-core.so";
    try std.testing.expectError(error.CoreUnavailable, prepare(io, allocator, &b, &.{b}, root, runtime));
    b.rom_path = "/missing-brick-test-content.nes";
    try std.testing.expectError(error.ContentUnavailable, prepare(io, allocator, &b, &.{b}, root, runtime));
}

test "Neo Geo missing BIOS is reported before emulator handoff" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try tmp.dir.realPathFileAlloc(io, ".", allocator);
    try tmp.dir.writeFile(io, .{ .sub_path = "game.zip", .data = "rom placeholder" });
    try tmp.dir.writeFile(io, .{ .sub_path = "fbneo_neogeo_libretro.so", .data = "core placeholder" });
    var game = catalog.games[0];
    game.rom_path = try std.Io.Dir.path.join(allocator, &.{ root, "game.zip" });
    game.core_path = try std.Io.Dir.path.join(allocator, &.{ root, "fbneo_neogeo_libretro.so" });
    const runtime = try std.Io.Dir.path.join(allocator, &.{ root, "run" });
    try std.testing.expectError(error.BiosUnavailable, prepare(io, allocator, &game, &.{game}, root, runtime));
    try tmp.dir.createDirPath(io, "BIOS");
    try tmp.dir.writeFile(io, .{ .sub_path = "BIOS/neogeo.zip", .data = "" });
    try std.testing.expectError(error.BiosUnavailable, prepare(io, allocator, &game, &.{game}, root, runtime));
    // Presence alone is not a claim of a valid BIOS set.
    try tmp.dir.writeFile(io, .{ .sub_path = "BIOS/neogeo.zip", .data = "presence fixture" });
    _ = try prepare(io, allocator, &game, &.{game}, root, runtime);
}
