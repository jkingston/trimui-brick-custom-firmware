// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const linux_backend = @import("linux_backend.zig");
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

fn snapshot(io: std.Io, allocator: std.mem.Allocator, path: []const u8, splash_screen: bool) !void {
    const pixels = try allocator.alloc(u32, render.width * render.height);
    defer allocator.free(pixels);
    const surface = render.Surface{ .pixels = pixels };
    var tree = if (splash_screen) ui.splash() else (model.Model{}).tree();
    surface.render(&tree);
    try writePpm(io, path, pixels);
}

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    _ = arguments.next();
    const command = arguments.next() orelse {
        try snapshot(init.io, init.gpa, "brick-home.ppm", false);
        return;
    };
    if (std.mem.eql(u8, command, "--snapshot")) {
        const path = arguments.next() orelse return error.MissingPath;
        const screen = arguments.next() orelse "home";
        try snapshot(init.io, init.gpa, path, std.mem.eql(u8, screen, "splash"));
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
    return error.UnknownCommand;
}

test {
    _ = linux_backend;
    _ = model;
    _ = scheduler;
}
