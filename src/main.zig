// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const linux_backend = @import("linux_backend.zig");
const launcher = @import("launcher.zig");
const media = @import("media.zig");
const model = @import("model.zig");
const render = @import("render.zig");
const scheduler = @import("scheduler.zig");
const ui = @import("ui.zig");

fn writePpm(io: std.Io, path: []const u8, pixels: []const u32) !void {
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

fn screenTree(name: []const u8) !ui.Tree {
    if (std.mem.eql(u8, name, "splash")) return ui.splash();
    if (std.mem.eql(u8, name, "classic")) return ui.classic();
    if (std.mem.eql(u8, name, "rich")) return ui.richLibrary();
    const page: model.Page = if (std.mem.eql(u8, name, "home")) .home else if (std.mem.eql(u8, name, "recent")) .recent else if (std.mem.eql(u8, name, "systems")) .systems else if (std.mem.eql(u8, name, "games")) .games else if (std.mem.eql(u8, name, "music")) .music else if (std.mem.eql(u8, name, "podcasts")) .podcasts else if (std.mem.eql(u8, name, "audiobooks")) .audiobooks else if (std.mem.eql(u8, name, "now-playing")) .now_playing else if (std.mem.eql(u8, name, "detail")) .game_detail else if (std.mem.eql(u8, name, "switcher")) .switcher else if (std.mem.eql(u8, name, "game-menu")) .quick_menu else if (std.mem.eql(u8, name, "checkpoints")) .checkpoints else if (std.mem.eql(u8, name, "game-settings")) .game_settings else if (std.mem.eql(u8, name, "storage")) .storage else if (std.mem.eql(u8, name, "empty-library")) .empty_library else if (std.mem.eql(u8, name, "save-data")) .save_data else if (std.mem.eql(u8, name, "save-conflict")) .save_conflict else if (std.mem.eql(u8, name, "ports")) .ports else return error.UnknownScreen;
    const selected: usize = if (page == .games) 3 else 0;
    var state = model.Model.preview(page, selected);
    return state.tree();
}

fn snapshot(io: std.Io, allocator: std.mem.Allocator, path: []const u8, screen: []const u8) !void {
    const pixels = try allocator.alloc(u32, render.width * render.height);
    defer allocator.free(pixels);
    const surface = render.Surface{ .pixels = pixels };
    var tree = try screenTree(screen);
    surface.render(&tree);
    try writePpm(io, path, pixels);
}

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    _ = arguments.next();
    const command = arguments.next() orelse {
        try snapshot(init.io, init.gpa, "brick-home.ppm", "home");
        return;
    };
    if (std.mem.eql(u8, command, "--snapshot")) {
        const path = arguments.next() orelse return error.MissingPath;
        const screen = arguments.next() orelse "home";
        try snapshot(init.io, init.gpa, path, screen);
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
    return error.UnknownCommand;
}

test {
    _ = linux_backend;
    _ = launcher;
    _ = media;
    _ = model;
    _ = scheduler;
}
