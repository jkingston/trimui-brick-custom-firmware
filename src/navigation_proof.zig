// SPDX-License-Identifier: GPL-2.0-only
// Host-only evidence renderer. Motion must be judged as a sequence, not from
// two static endpoints, so this keeps a deterministic filmstrip near the code.
const std = @import("std");
const navigation = @import("navigation_motion.zig");
const render = @import("render.zig");
const ui = @import("ui.zig");

fn writeFrames(
    io: std.Io,
    allocator: std.mem.Allocator,
    directory: []const u8,
    name: []const u8,
    from: *const @import("ui_scene.zig").Tree,
    to: *const @import("ui_scene.zig").Tree,
    direction: navigation.Direction,
    times: []const i64,
) !void {
    const pixels = try allocator.alloc(u32, render.width * render.height);
    defer allocator.free(pixels);
    var controller = navigation.Controller{};
    controller.begin(from, to, direction, 0, false);
    for (times, 0..) |time, index| {
        (render.Surface{ .pixels = pixels }).renderTransition(controller.frame(time));
        var path_buffer: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}-{d}.ppm", .{ directory, name, index });
        try @import("main.zig").writePpm(io, path, pixels);
    }
}

pub fn main(init: std.process.Init) !void {
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    _ = arguments.next();
    const directory = arguments.next() orelse "output/motion-proof";
    const theme = @import("theme.zig").dark;
    var quick = ui.overlayPause(theme, "FALLING", 2, 0, "Bright", "");
    var states = ui.overlayStates(theme, "FALLING", 0, "", .{ true, false, false, true });
    try writeFrames(init.io, init.gpa, directory, "forward", &quick, &states, .forward, &.{ 0, 48, 96, 167 });
    try writeFrames(init.io, init.gpa, directory, "back", &states, &quick, .back, &.{ 0, 40, 80, 120 });
}
