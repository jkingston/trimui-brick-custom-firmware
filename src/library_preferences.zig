// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const model = @import("model.zig");
const ui = @import("ui.zig");

const Preferences = struct {
    view: []const u8,
    rom: []const u8,
    system: ?[]const u8 = null,
    last_rom: []const u8 = "",
    recent: []const []const u8 = &.{},
};

fn viewFromName(name: []const u8) ?ui.LibraryView {
    if (std.mem.eql(u8, name, "recent")) return .recent;
    if (std.mem.eql(u8, name, "all")) return .all;
    return null;
}

pub fn load(io: std.Io, dir: std.Io.Dir, state: *model.Model) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const contents = dir.readFileAlloc(io, "library.json", allocator, .limited(16384)) catch return;
    const saved = std.json.parseFromSliceLeaky(Preferences, allocator, contents, .{}) catch return;
    if (viewFromName(saved.view)) |view| state.library_view = view;
    if (saved.system) |label| {
        for (@import("catalog.zig").systems, 0..) |system, index| {
            if (std.mem.eql(u8, label, system.label) and state.hasSystem(index)) state.system = index;
        }
    }
    var selected_source: ?usize = null;
    for (state.games, 0..) |game, index| {
        if (std.mem.eql(u8, game.rom_path, saved.last_rom)) state.last_played = index;
        if (std.mem.eql(u8, game.rom_path, saved.rom)) selected_source = index;
    }
    for (saved.recent) |path| {
        for (state.games, 0..) |game, index| if (std.mem.eql(u8, game.rom_path, path)) {
            var duplicate = false;
            for (state.recent[0..state.recent_len]) |source| duplicate = duplicate or source == index;
            if (!duplicate and state.recent_len < state.recent.len) {
                state.recent[state.recent_len] = index;
                state.recent_len += 1;
            }
            break;
        };
    }
    // Old preferences had only `last_rom`; preserve it as the first factual
    // history item instead of inventing history from alphabetical order.
    if (state.recent_len == 0) if (state.last_played) |index| {
        state.recent[0] = index;
        state.recent_len = 1;
    };
    if (selected_source) |index| if (state.collection().positionOf(index)) |position| {
        state.library_selection = position;
        if (state.page == .games) {
            state.selected = position;
            state.library_preview = position;
        }
    };
}

pub fn save(io: std.Io, dir: std.Io.Dir, state: *const model.Model) !void {
    var recent: [model.maximum_history][]const u8 = @splat("");
    for (state.recent[0..state.recent_len], 0..) |source, index| recent[index] = state.games[source].rom_path;
    const saved = Preferences{
        .view = @tagName(state.library_view),
        .rom = if (state.librarySource()) |index| state.games[index].rom_path else "",
        .system = if (state.system != null) state.collection().label() else null,
        .last_rom = if (state.last_played) |index| state.games[index].rom_path else "",
        .recent = recent[0..state.recent_len],
    };
    const contents = try std.json.Stringify.valueAlloc(std.heap.page_allocator, saved, .{});
    defer std.heap.page_allocator.free(contents);
    try dir.writeFile(io, .{ .sub_path = "library.json.tmp", .data = contents });
    try dir.rename("library.json.tmp", dir, "library.json", io);
}

test "library preferences restore by path after the library is reordered" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var state = model.Model{ .page = .games, .selected = 1, .library_view = .all };
    try save(std.testing.io, temporary.dir, &state);
    const original = state.games[1];
    const reordered = [_]@import("catalog.zig").Game{original};
    state = .{ .games = &reordered };
    load(std.testing.io, temporary.dir, &state);
    try std.testing.expectEqual(ui.LibraryView.all, state.library_view);
    try std.testing.expectEqual(@as(usize, 0), state.selected);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "library.json", .data = "broken" });
    load(std.testing.io, temporary.dir, &state);
    try std.testing.expectEqual(@as(usize, 0), state.selected);
}
