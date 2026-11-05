// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const model = @import("model.zig");
const ui = @import("ui.zig");

const Preferences = struct { view: ui.LibraryView, rom: []const u8, system: ?[]const u8 = null, last_rom: []const u8 = "" };

pub fn load(io: std.Io, dir: std.Io.Dir, state: *model.Model) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const contents = dir.readFileAlloc(io, "library.json", allocator, .limited(16384)) catch return;
    const saved = std.json.parseFromSliceLeaky(Preferences, allocator, contents, .{}) catch return;
    state.library_view = saved.view;
    if (saved.system) |label| {
        for (@import("catalog.zig").systems, 0..) |system, index| {
            if (std.mem.eql(u8, label, system.label) and state.hasSystem(index)) state.system = index;
        }
    }
    for (state.games, 0..) |game, index| {
        if (std.mem.eql(u8, game.rom_path, saved.last_rom)) state.last_played = index;
        if (std.mem.eql(u8, game.rom_path, saved.rom)) {
            if (state.collection().positionOf(index)) |position| {
                state.library_selection = position;
                if (state.page == .games) state.selected = position;
            }
        }
    }
}

pub fn save(io: std.Io, dir: std.Io.Dir, state: *const model.Model) !void {
    const saved = Preferences{
        .view = state.library_view,
        .rom = if (state.librarySource()) |index| state.games[index].rom_path else "",
        .system = if (state.system != null) state.collection().label() else null,
        .last_rom = if (state.last_played) |index| state.games[index].rom_path else "",
    };
    const contents = try std.json.Stringify.valueAlloc(std.heap.page_allocator, saved, .{});
    defer std.heap.page_allocator.free(contents);
    try dir.writeFile(io, .{ .sub_path = "library.json.tmp", .data = contents });
    try dir.rename("library.json.tmp", dir, "library.json", io);
}

test "library preferences restore by path after the library is reordered" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var state = model.Model{ .page = .games, .selected = 1, .library_view = .shelf };
    try save(std.testing.io, temporary.dir, &state);
    const original = state.games[1];
    const reordered = [_]@import("catalog.zig").Game{original};
    state = .{ .games = &reordered };
    load(std.testing.io, temporary.dir, &state);
    try std.testing.expectEqual(ui.LibraryView.shelf, state.library_view);
    try std.testing.expectEqual(@as(usize, 0), state.selected);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "library.json", .data = "broken" });
    load(std.testing.io, temporary.dir, &state);
    try std.testing.expectEqual(@as(usize, 0), state.selected);
}
