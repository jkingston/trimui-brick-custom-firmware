// SPDX-License-Identifier: GPL-2.0-only
// Device-only comparison; never used as a runtime fallback.
const std = @import("std");
const ui = @import("ui.zig");
const render = @import("render.zig");
const gpu = @import("gpu_renderer.zig");
const c = @import("gpu_abi.zig");

pub fn artwork(io: std.Io, display: *gpu.Display, expected: []u32) !void {
    // SAFETY: Only entries initialized by the following loop are read.
    var pixels: [64 * 64]u32 = undefined;
    for (&pixels, 0..) |*pixel, i| pixel.* = @bitCast(ui.Color{
        .r = @intCast(i % 251),
        .g = @intCast((i * 7) % 251),
        .b = @intCast((i * 13) % 251),
        .a = switch (i % 3) {
            0 => 0,
            1 => 128,
            else => 255,
        },
    });
    const texture = @import("asset_manifest.zig").Texture{ .width = 64, .height = 64, .pixels = &pixels, .content_x = 2, .content_y = 3, .content_width = 60, .content_height = 58 };
    for ([_]i16{ -2400, 0, 2400 }) |tilt| for ([_]u8{ 0, 97, 255 }) |dim| for ([_]u16{ 0, 17 }) |clip| {
        var tree = ui.Tree{ .theme = @import("theme.zig").light, .background = @import("theme.zig").light.background };
        tree.add(.{ .cartridge = .{ .bounds = .{ .x = 48, .y = 130, .width = 331, .height = 287 }, .platform = "gba", .texture = null, .sprite = texture, .dim = dim, .tilt = tilt, .clip_left = clip } });
        try display.show(io, &tree);
        (render.Surface{ .pixels = expected }).render(&tree);
        try display.verify(expected);
    };
    std.log.info("GPU oracle PASS: cropped, alpha, dimmed, tilted and clipped artwork", .{});
}

pub fn fineDamage(io: std.Io, display: *gpu.Display, expected: []u32) !void {
    const labels = [_][]const u8{ "Initial label", "Short", "A much longer label with descenders gyp", "", "日本語", "العربية" };
    for ([_]ui.Theme{ @import("theme.zig").light, @import("theme.zig").dark }) |theme| {
        for (0..24) |frame| {
            var tree = ui.Tree{ .theme = theme, .background = theme.background };
            tree.add(.{ .overlay_row = .{ .bounds = .{ .x = 28, .y = 138, .width = 968, .height = 108 }, .label = labels[frame % labels.len], .detail = if (frame % 3 == 0) "Detail with descenders" else "", .value = if (frame % 2 == 0) "On" else "", .selected = false } });
            tree.add(.{ .scrim = .{ .bounds = .{ .x = 100, .y = 170, .width = 800, .height = 30 }, .color = theme.danger, .alpha = 127 } });
            try display.show(io, &tree);
            (render.Surface{ .pixels = expected }).render(&tree);
            try display.verify(expected);
        }
        for (0..40) |frame| {
            var tree = ui.wifiPassword(theme, "Example", @intCast(frame), "", frame >= 20);
            try display.show(io, &tree);
            (render.Surface{ .pixels = expected }).render(&tree);
            try display.verify(expected);
        }
    }
    std.log.info("GPU oracle PASS: 48 clipped text/alpha and 80 keyboard frames", .{});
    for (0..16) |frame| {
        var tree = ui.Tree{ .background = @import("theme.zig").dark.background };
        for (0..16) |row| {
            const value: u8 = @intCast(frame * 16 + row);
            const color = ui.Color{ .r = value, .g = 255 - value, .b = value *% 73 };
            const y: u16 = @intCast(20 + row * 44);
            tree.add(.{ .bar = .{ .bounds = .{ .x = 32, .y = y, .width = 64, .height = 32 }, .color = color, .radius = 0 } });
            tree.add(.{ .scrim = .{ .bounds = .{ .x = 120, .y = y, .width = 64, .height = 32 }, .color = color, .alpha = value } });
        }
        try display.show(io, &tree);
        (render.Surface{ .pixels = expected }).render(&tree);
        try display.verify(expected);
    }
    std.log.info("GPU oracle PASS: all 256 vertex colour and alpha values in 16 frames", .{});
}

pub fn shelfDamage(io: std.Io, display: *gpu.Display, expected: []u32) !void {
    for ([_]ui.Theme{ @import("theme.zig").light, @import("theme.zig").dark }) |theme| {
        for (0..24) |frame| {
            var tree = ui.library(theme, &@import("catalog.zig").games, frame / 6, .shelf, @as(i16, @intCast(frame * 137 % 2001)) - 1000);
            if (frame % 2 == 0) render.prepareText(&tree);
            try display.show(io, &tree);
            (render.Surface{ .pixels = expected }).render(&tree);
            try display.verify(expected);
        }
    }
    std.log.info("GPU oracle PASS: 48 resized shelf frames", .{});
}

pub fn asynchronous(io: std.Io, display: *gpu.Display, expected: []u32) !void {
    for (0..24) |frame| {
        var tree = ui.settings(frame % 7, .{}, "On", "Off");
        try display.submit(io, &tree);
        if (!display.inFlight()) return error.MissingPendingFlip;
        if (display.submit(io, &tree)) |_| return error.PendingBufferReused else |err| {
            if (err != error.FramePending) return err;
        }
        try display.wait(io);
        (render.Surface{ .pixels = expected }).render(&tree);
        try display.verify(expected);
    }
    std.log.info("GPU oracle PASS: 24 asynchronous buffer-ownership frames", .{});
    const profiling = display.profiling;
    display.profiling = true;
    defer display.profiling = profiling;
    var cells: [65 * 65]u8 = undefined;
    for (0..12) |frame| {
        for (&cells, 0..) |*cell, i| cell.* = @intFromBool((i + frame) % 3 != 0);
        const theme = if (frame % 2 == 0) @import("theme.zig").light else @import("theme.zig").dark;
        var tree = ui.Tree{ .theme = theme, .background = theme.background };
        tree.add(.{ .qr_code = .{ .bounds = .{ .x = 200, .y = 100, .width = 432, .height = 432 }, .cells = &cells, .width = 65, .foreground = theme.text, .background = theme.background } });
        try display.show(io, &tree);
        if (display.last.draw_calls < 4) return error.VertexBatchCapacityNotExercised;
        (render.Surface{ .pixels = expected }).render(&tree);
        try display.verify(expected);
    }
    std.log.info("GPU oracle PASS: 12 frames reusing vertex storage across capacity flushes", .{});
    const labels = "0123456789ABCDEFGHIJKLMNOPQRSTUV";
    const capacity = @import("texture_batch.zig").capacity;
    const expected_draws = (labels.len + capacity - 1) / capacity;
    for (0..8) |frame| {
        var theme = if (frame % 2 == 0) @import("theme.zig").light else @import("theme.zig").dark;
        theme.background.r += @intCast(frame);
        var tree = ui.Tree{ .theme = theme, .background = theme.background };
        for (0..labels.len) |index| tree.add(.{ .text = .{
            .bounds = .{ .x = @intCast(40 + index / 16 * 480), .y = @intCast(20 + index % 16 * 44), .width = 200, .height = 40 },
            .value = labels[index..][0..1],
            .color = theme.text,
            .font = @import("design.zig").typeface.caption,
        } });
        try display.show(io, &tree);
        if (frame != 0 and (display.last.draw_calls != expected_draws or display.last.upload_bytes != 0 or display.last.damage_pixels != render.width * render.height)) {
            std.log.err("texture rollover frame={d} draws={d} expected={d} uploads={d} damage={d}", .{ frame, display.last.draw_calls, expected_draws, display.last.upload_bytes, display.last.damage_pixels });
            return error.TextureBatchCapacityNotExercised;
        }
        (render.Surface{ .pixels = expected }).render(&tree);
        try display.verify(expected);
    }
    std.log.info("GPU oracle PASS: 8 frames covering all texture slots and batch rollover", .{});
    var evictions: usize = 0;
    for (0..16) |frame| {
        const theme = @import("theme.zig").light;
        var tree = ui.Tree{ .theme = theme, .background = theme.background };
        tree.background.g -= @intCast(frame);
        var font = @import("design.zig").typeface.caption;
        font.size = @intCast(20 + frame % 4 * 5);
        for (0..labels.len) |index| tree.add(.{ .text = .{
            .bounds = .{ .x = @intCast(40 + index / 16 * 480), .y = @intCast(20 + index % 16 * 44), .width = 200, .height = 40 },
            .value = labels[index..][0..1],
            .color = theme.text,
            .font = font,
        } });
        try display.show(io, &tree);
        evictions += display.last.texture_evictions;
        (render.Surface{ .pixels = expected }).render(&tree);
        try display.verify(expected);
    }
    if (evictions < 32) return error.TextureEvictionNotExercised;
    std.log.info("GPU oracle PASS: 16 texture-eviction frames, {d} evictions", .{evictions});
    for (0..24) |frame| {
        var tree = benchTree(.tiny, frame);
        const positions = [_][2]u16{ .{ 0, 0 }, .{ 1, 1 }, .{ 1003, 747 }, .{ 1004, 748 } };
        const position = positions[frame / 6];
        tree.elements[0].bar.bounds.x = position[0];
        tree.elements[0].bar.bounds.y = position[1];
        try display.show(io, &tree);
        if (frame % 6 >= 2 and (display.last.draw_calls != 0 or display.last.clear_calls != 1 or display.last.damage_pixels != 400))
            return error.SingleClearNotExercised;
        (render.Surface{ .pixels = expected }).render(&tree);
        try display.verify(expected);
    }
    std.log.info("GPU oracle PASS: 24 single-clear frames at screen boundaries", .{});
}

const Workload = enum { selection, selection_cycle, navigation, scrolling, value, keyboard, shelf, shelf_dynamic, shelf_prepared, tiny, full, idle, idle_retained, unchanged };

fn benchTree(workload: Workload, frame: usize) ui.Tree {
    return switch (workload) {
        .selection, .idle_retained => ui.settings(frame % 2, .{}, "On", "Off"),
        .selection_cycle, .idle => ui.settings(frame % 3, .{}, "On", "Off"),
        .navigation => ui.settings(if (frame % 12 <= 6) frame % 12 else 12 - frame % 12, .{}, "On", "Off"),
        .scrolling => ui.settings(2 + frame % 4, .{}, "On", "Off"),
        .value => ui.overlayPause(@import("theme.zig").light, "Example", 1, frame % 3, "Balanced", ""),
        .keyboard => ui.wifiPassword(@import("theme.zig").light, "Example", @intCast(frame % 36), "", false),
        .shelf => ui.library(@import("theme.zig").light, &@import("catalog.zig").games, 2, .shelf, @as(i16, @intCast(frame % 20)) * 100 - 1000),
        .shelf_dynamic, .shelf_prepared => ui.library(@import("theme.zig").light, &@import("catalog.zig").games, 2, .shelf, @as(i16, @intCast(frame * 37 % 2001)) - 1000),
        .unchanged => ui.settings(0, .{}, "On", "Off"),
        .tiny, .full => blk: {
            const theme = @import("theme.zig").light;
            var tree = ui.Tree{ .theme = theme, .background = theme.background };
            tree.add(.{ .bar = .{
                .bounds = .{ .x = 0, .y = 0, .width = if (workload == .tiny) 20 else 1024, .height = if (workload == .tiny) 20 else 768 },
                .color = switch (frame % 3) {
                    0 => theme.text,
                    1 => theme.surface,
                    else => theme.muted,
                },
                .radius = 0,
            } });
            break :blk tree;
        },
    };
}

pub fn benchmark(io: std.Io, selected: ?[]const u8) !void {
    const only = if (selected) |name| std.meta.stringToEnum(Workload, name) orelse return error.UnknownWorkload else null;
    const display = try gpu.Display.open();
    defer display.close();
    display.profiling = true;
    for (std.enums.values(Workload)) |workload| {
        if (only != null and only.? != workload) continue;
        const sleeping = workload == .idle or workload == .idle_retained;
        const count: usize = if (sleeping) 16 else 120;
        var timings: [120]i64 = @splat(0);
        var totals: gpu.Profile = .{};
        var before = std.mem.zeroes(c.Usage);
        for (0..count + 20) |i| {
            if (i == 20 and c.getrusage(0, &before) != 0) return error.ResourceUsage;
            if (sleeping) _ = c.usleep(250000);
            var tree = benchTree(workload, i);
            const preparing = std.Io.Timestamp.now(io, .awake);
            if (workload == .shelf_prepared) render.prepareText(&tree);
            const prepare_us = if (workload == .shelf_prepared) preparing.durationTo(std.Io.Timestamp.now(io, .awake)).toMicroseconds() else 0;
            try display.show(io, &tree);
            display.last.prepare_us = prepare_us;
            if (i < 20) continue;
            timings[i - 20] = prepare_us + display.last.scene_us + display.last.submit_us + display.last.complete_us;
            inline for (@typeInfo(gpu.Profile).@"struct".field_names) |field| {
                @field(totals, field) += @field(display.last, field);
            }
        }
        var after = std.mem.zeroes(c.Usage);
        if (c.getrusage(0, &after) != 0) return error.ResourceUsage;
        const cpu = (after.user.seconds + after.system.seconds - before.user.seconds - before.system.seconds) * 1_000_000 + after.user.micros + after.system.micros - before.user.micros - before.system.micros;
        std.mem.sort(i64, timings[0..count], {}, std.sort.asc(i64));
        const n: i64 = @intCast(count);
        std.log.info("GPU {s}: p50={d}us p95={d}us p99={d}us prepare={d}us scene={d}us submit={d}us wait={d}us present={d}us CPU={d}us draws={d:.2} clears={d:.2} uploads={d}B damage={d}px RSS={d}KiB", .{
            @tagName(workload),
            timings[count / 2],
            timings[count * 95 / 100],
            timings[count * 99 / 100],
            @divTrunc(totals.prepare_us, n),
            @divTrunc(totals.scene_us, n),
            @divTrunc(totals.submit_us, n),
            @divTrunc(totals.complete_us, n),
            @divTrunc(totals.present_us, n),
            @divTrunc(cpu, n),
            @as(f64, @floatFromInt(totals.draw_calls)) / @as(f64, @floatFromInt(count)),
            @as(f64, @floatFromInt(totals.clear_calls)) / @as(f64, @floatFromInt(count)),
            totals.upload_bytes / count,
            totals.damage_pixels / count,
            after.counters[0],
        });
        std.log.info("GPU completion: create={d}us wait={d}us destroy={d}us", .{
            @divTrunc(totals.fence_create_us, n),
            @divTrunc(totals.fence_wait_us, n),
            @divTrunc(totals.fence_destroy_us, n),
        });
        std.log.info("GPU submission: target={d}us state={d}us draw={d}us clear={d}us", .{
            @divTrunc(totals.target_us, n),
            @divTrunc(totals.draw_state_us, n),
            @divTrunc(totals.draw_us, n),
            @divTrunc(totals.clear_us, n),
        });
    }
}
