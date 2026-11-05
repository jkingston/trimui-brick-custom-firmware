// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const catalog = @import("catalog.zig");
const linux_backend = @import("linux_backend.zig");
const library_scan = @import("library_scan.zig");
const model = @import("model.zig");
const overlay = @import("overlay.zig");
const render = @import("render.zig");
const scheduler = @import("scheduler.zig");
const ui = @import("ui.zig");

pub fn writePpm(io: std.Io, path: []const u8, pixels: []const u32) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var output_buffer: [16 * 1024]u8 = undefined;
    var writer = file.writer(io, &output_buffer);
    var header: [64]u8 = undefined;
    const text = try std.fmt.bufPrint(&header, "P6\n{d} {d}\n255\n", .{ render.width, render.height });
    try writer.interface.writeAll(text);
    var row: [render.width * 3]u8 = undefined;
    var y: usize = 0;
    while (y < render.height) : (y += 1) {
        for (pixels[y * render.width .. (y + 1) * render.width], 0..) |pixel, x| {
            row[x * 3] = @truncate(pixel >> 16);
            row[x * 3 + 1] = @truncate(pixel >> 8);
            row[x * 3 + 2] = @truncate(pixel);
        }
        try writer.interface.writeAll(&row);
    }
    try writer.interface.flush();
}

fn snapshot(io: std.Io, allocator: std.mem.Allocator, path: []const u8, screen: []const u8, games: ?[]const catalog.Game, selected: usize) !void {
    const pixels = try allocator.alloc(u32, render.width * render.height);
    defer allocator.free(pixels);
    @memset(pixels, 0xff13253c);
    const surface = render.Surface{ .pixels = pixels };
    var state = model.Model{};
    if (std.mem.eql(u8, screen, "home")) state.page = .home;
    if (games) |library| {
        state.games = library;
        if (library.len > 0) {
            state.selected = @min(selected, library.len - 1);
            state.game_index = state.selected;
        }
    }
    if (std.mem.eql(u8, screen, "games") or std.mem.eql(u8, screen, "games-shelf") or std.mem.eql(u8, screen, "games-grid")) {
        state.page = .games;
        if (std.mem.eql(u8, screen, "games-shelf")) state.library_view = .shelf;
        if (std.mem.eql(u8, screen, "games-grid")) state.library_view = .grid;
    } else if (std.mem.eql(u8, screen, "game")) {
        state.page = .game;
        if (games == null) state.game_index = 1;
    } else if (std.mem.eql(u8, screen, "settings")) {
        state.page = .settings;
    }
    var tree = if (std.mem.eql(u8, screen, "splash")) ui.splash() else if (std.mem.eql(u8, screen, "languages")) ui.languageProof() else if (std.mem.eql(u8, screen, "overlay")) blk: {
        const game_overlay = overlay.Model{};
        break :blk game_overlay.tree();
    } else if (std.mem.eql(u8, screen, "overlay-states")) blk: {
        var game_overlay = overlay.Model{};
        game_overlay.layer = .states;
        game_overlay.state_slot = 1;
        break :blk game_overlay.tree();
    } else state.tree();
    surface.render(&tree);
    try writePpm(io, path, pixels);
}

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    _ = arguments.next();
    const command = arguments.next() orelse {
        try snapshot(init.io, init.gpa, "brick-home.ppm", "home", null, 0);
        return;
    };
    if (std.mem.eql(u8, command, "--snapshot")) {
        const path = arguments.next() orelse return error.MissingPath;
        const screen = arguments.next() orelse "home";
        try snapshot(init.io, init.gpa, path, screen, null, 0);
        return;
    }
    if (std.mem.eql(u8, command, "--snapshot-library")) {
        const path = arguments.next() orelse return error.MissingPath;
        const screen = arguments.next() orelse "games";
        const root = arguments.next() orelse "/data";
        const selected = if (arguments.next()) |value| try std.fmt.parseInt(usize, value, 10) else 0;
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        defer arena.deinit();
        const library = try catalog.discover(init.io, arena.allocator(), root);
        try snapshot(init.io, arena.allocator(), path, screen, library, selected);
        return;
    }
    if (std.mem.eql(u8, command, "--idle-proof")) {
        var plan = scheduler.Scheduler{};
        plan.rendered(0);
        if (plan.nextWake(1) != null) return error.UnexpectedWakeup;
        return;
    }
    if (std.mem.eql(u8, command, "--run")) {
        try linux_backend.run(init.io);
        return;
    }
    if (std.mem.eql(u8, command, "--probe")) {
        try linux_backend.probe(init.io);
        return;
    }
    if (std.mem.eql(u8, command, "--scan-library")) {
        const root = arguments.next() orelse "/data";
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        defer arena.deinit();
        try library_scan.write(init.io, arena.allocator(), root);
        return;
    }
    return error.UnknownCommand;
}

test {
    _ = render;
    _ = linux_backend;
    _ = model;
    _ = overlay;
    _ = @import("retroarch.zig");
    _ = scheduler;
    _ = @import("settings.zig");
    _ = @import("asset_manifest.zig");
    _ = @import("input_repeat.zig");
    _ = library_scan;
    _ = @import("shelf_motion.zig");
    _ = @import("library_preferences.zig");
}
