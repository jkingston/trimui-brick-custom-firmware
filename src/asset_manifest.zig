// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

const maximum_manifest_bytes = 16 * 1024 * 1024;

const Entry = struct {
    rom: []const u8,
    platform: []const u8,
    match: []const u8,
    title: []const u8,
    game_id: ?[]const u8 = null,
    model: ?[]const u8 = null,
    surfaces: ?std.json.Value = null,
    note: ?[]const u8 = null,
};

const Manifest = struct {
    schema_version: u32,
    asset_index_version: ?[]const u8,
    games: []const Entry,
    attribution: std.json.Value,
};

pub const Assets = struct {
    model: ?[]const u8 = null,
    front: ?[]const u8 = null,
    top: ?[]const u8 = null,
    rear: ?[]const u8 = null,
    disc: ?[]const u8 = null,
};

fn confinedPath(allocator: std.mem.Allocator, root: []const u8, relative: []const u8) ![]const u8 {
    if (std.Io.Dir.path.isAbsolute(relative)) return error.AssetPathEscapesRoot;
    const resolved_root = try std.Io.Dir.path.resolve(allocator, &.{root});
    const resolved = try std.Io.Dir.path.resolve(allocator, &.{ resolved_root, relative });
    if (!std.mem.eql(u8, resolved, resolved_root)) {
        if (!std.mem.startsWith(u8, resolved, resolved_root) or
            resolved.len <= resolved_root.len or resolved[resolved_root.len] != std.Io.Dir.path.sep)
            return error.AssetPathEscapesRoot;
    }
    return resolved;
}

fn surfacePath(allocator: std.mem.Allocator, asset_root: []const u8, surfaces: ?std.json.Value, name: []const u8) !?[]const u8 {
    const value = surfaces orelse return null;
    if (value != .object) return error.InvalidAssetSurfaces;
    const member = value.object.get(name) orelse return null;
    if (member != .string) return error.InvalidAssetSurfaces;
    return try confinedPath(allocator, asset_root, member.string);
}

fn modelPath(allocator: std.mem.Allocator, asset_root: []const u8, id: ?[]const u8) !?[]const u8 {
    const value = id orelse return null;
    if (value.len == 0) return error.InvalidAssetModel;
    for (value) |character| {
        if (!std.ascii.isAlphanumeric(character) and character != '-')
            return error.InvalidAssetModel;
    }
    const relative = try std.fmt.allocPrint(allocator, "models/{s}.glb", .{value});
    return try confinedPath(allocator, asset_root, relative);
}

pub fn load(io: std.Io, allocator: std.mem.Allocator, data_root: []const u8) !std.StringHashMap(Assets) {
    var result: std.StringHashMap(Assets) = .init(allocator);
    const asset_root = try std.Io.Dir.path.join(allocator, &.{ data_root, "Assets", "Brick" });
    const manifest_path = try std.Io.Dir.path.join(allocator, &.{ asset_root, "library.json" });
    const contents = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(maximum_manifest_bytes)) catch |err| switch (err) {
        error.FileNotFound => return result,
        else => return err,
    };
    const manifest = try std.json.parseFromSliceLeaky(Manifest, allocator, contents, .{ .ignore_unknown_fields = false, .allocate = .alloc_always });
    if (manifest.schema_version != 1) return error.UnsupportedAssetManifest;
    for (manifest.games) |entry| {
        if (entry.model == null or entry.surfaces == null) continue;
        const rom = try confinedPath(allocator, data_root, entry.rom);
        const assets = Assets{
            .model = try modelPath(allocator, asset_root, entry.model),
            .front = try surfacePath(allocator, asset_root, entry.surfaces, "artwork.front"),
            .top = try surfacePath(allocator, asset_root, entry.surfaces, "artwork.top"),
            .rear = try surfacePath(allocator, asset_root, entry.surfaces, "artwork.rear"),
            .disc = try surfacePath(allocator, asset_root, entry.surfaces, "artwork.disc"),
        };
        try result.put(rom, assets);
    }
    return result;
}

test "manifest maps confined ROM and artwork paths" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.createDirPath(io, "Assets/Brick");
    try temporary.dir.writeFile(io, .{ .sub_path = "Assets/Brick/library.json", .data =
        \\{"schema_version":1,"asset_index_version":"test","games":[
        \\{"rom":"Roms/GB/Tetris.gb","platform":"gb","match":"crc32","title":"Tetris","model":"gb","surfaces":{"artwork.front":"objects/aa/label.png"}}
        \\],"attribution":{}}
    });
    var assets = try load(io, allocator, root);
    defer assets.deinit();
    const rom = try std.Io.Dir.path.join(allocator, &.{ root, "Roms/GB/Tetris.gb" });
    const mapped = assets.get(rom).?;
    try std.testing.expect(std.mem.endsWith(u8, mapped.model.?, "/Assets/Brick/models/gb.glb"));
    try std.testing.expect(std.mem.endsWith(u8, mapped.front.?, "/Assets/Brick/objects/aa/label.png"));
}

test "manifest rejects model path injection" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.createDirPath(io, "Assets/Brick");
    try temporary.dir.writeFile(io, .{ .sub_path = "Assets/Brick/library.json", .data =
        \\{"schema_version":1,"asset_index_version":"test","games":[
        \\{"rom":"Roms/GB/Tetris.gb","platform":"gb","match":"name","title":"Tetris","model":"../../escape","surfaces":{"artwork.front":"objects/label.png"}}
        \\],"attribution":{}}
    });
    try std.testing.expectError(error.InvalidAssetModel, load(io, allocator, root));
}

test "manifest rejects paths outside the data and asset roots" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.createDirPath(io, "Assets/Brick");
    try temporary.dir.writeFile(io, .{ .sub_path = "Assets/Brick/library.json", .data =
        \\{"schema_version":1,"asset_index_version":"test","games":[
        \\{"rom":"../escape.gb","platform":"gb","match":"name","title":"Escape","model":"gb","surfaces":{"artwork.front":"objects/label.png"}}
        \\],"attribution":{}}
    });
    try std.testing.expectError(error.AssetPathEscapesRoot, load(io, allocator, root));
}
