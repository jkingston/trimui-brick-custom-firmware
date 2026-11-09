// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const frame_pacer = @import("frame_pacer.zig");
const gpu_renderer = @import("gpu_renderer.zig");
const input_latency = @import("input_latency.zig");
const ui = @import("ui_scene.zig");

const blank_path = "/sys/class/graphics/fb0/blank";
const maximum_poll_fds = 12;

pub const Scheduler = struct {
    io: std.Io,
    gpu: *gpu_renderer.Display,
    profiling: bool,
    unblanked: bool = false,
    pending_input: input_latency.Pending = .{},
    in_flight_input: input_latency.Pending = .{},
    render_started_us: i64 = 0,
    render_target_us: i64 = 0,
    render_budget_us: i64 = 0,
    dirty: bool = false,
    pacer: frame_pacer.Pacer = .{},

    pub fn open(io: std.Io, profiling: bool) !Scheduler {
        const gpu = try gpu_renderer.Display.open();
        gpu.profiling = profiling;
        return .{ .io = io, .gpu = gpu, .profiling = profiling };
    }

    pub fn close(self: *Scheduler) void {
        self.finishPending() catch |err| std.log.err("display completion failed: {s}", .{@errorName(err)});
        self.gpu.close();
    }

    pub fn show(self: *Scheduler, tree: *const ui.Tree) !void {
        try self.finishPending();
        try self.submit(tree);
        try self.finishPending();
    }

    pub fn submit(self: *Scheduler, tree: *const ui.Tree) !void {
        self.render_started_us = if (self.profiling) nowMicroseconds(self.io) else 0;
        if (self.profiling) {
            self.render_target_us = self.pacer.target_us;
            self.render_budget_us = self.pacer.budget_us;
        }
        try self.gpu.submit(self.io, tree);
        self.pacer.painted(self.gpu.last_work_us);
        self.dirty = false;
        self.in_flight_input = self.pending_input;
        self.pending_input = .{};
        if (!self.gpu.inFlight()) self.reportFrame();
        if (!self.unblanked) {
            try writeAttribute(self.io, blank_path, "0\n");
            self.unblanked = true;
        }
    }

    pub fn recordInput(self: *Scheduler, event_us: i64) void {
        if (self.profiling) self.pending_input.recordAt(event_us, nowMicroseconds(self.io));
    }

    pub fn requestFrame(self: *Scheduler, tree: ?*const ui.Tree) !void {
        self.dirty = true;
        if (self.gpu.inFlight()) return;
        _ = tree;
        if (self.pacer.due_us != null) return;
        const timing = try self.gpu.presenter.?.timing();
        self.pacer.request(nowMicroseconds(self.io), timing.vblank_us, timing.period_us);
    }

    pub fn frameDue(self: *Scheduler) bool {
        return self.dirty and !self.gpu.inFlight() and self.pacer.ready(nowMicroseconds(self.io));
    }

    pub fn poll(self: *Scheduler, fds: []std.posix.pollfd, timeout_ms: i32) !usize {
        if (!self.gpu.inFlight() and self.pacer.due_us == null) return std.posix.poll(fds, timeout_ms);
        if (fds.len + 1 > maximum_poll_fds) return error.PollCapacity;
        var merged: [maximum_poll_fds]std.posix.pollfd = @splat(.{ .fd = -1, .events = std.posix.POLL.IN, .revents = 0 });
        @memcpy(merged[0..fds.len], fds);
        if (self.gpu.inFlight()) merged[fds.len].fd = self.gpu.fd;
        while (true) {
            var micros: i64 = if (timeout_ms < 0) std.math.maxInt(i32) else @as(i64, timeout_ms) * 1000;
            if (self.gpu.inFlight()) {
                micros = @min(micros, try self.gpu.presenter.?.remainingUs());
            } else if (self.pacer.due_us != null) {
                micros = @min(micros, self.pacer.waitUs(nowMicroseconds(self.io), timeout_ms));
            }
            const timeout = std.posix.timespec{ .sec = @intCast(@divTrunc(micros, 1_000_000)), .nsec = @intCast(@mod(micros, 1_000_000) * 1000) };
            var ready = std.posix.ppoll(merged[0 .. fds.len + 1], &timeout, null) catch |err| switch (err) {
                error.SignalInterrupt => continue,
                else => return err,
            };
            @memcpy(fds, merged[0..fds.len]);
            const drm_events = merged[fds.len].revents;
            if ((drm_events & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0) return error.DrmFlipPoll;
            if ((drm_events & std.posix.POLL.IN) != 0) {
                ready -= 1;
                if (try self.gpu.dispatch(self.io)) {
                    self.reportFrame();
                    if (self.dirty) try self.requestFrame(null);
                }
            }
            return ready;
        }
    }

    fn finishPending(self: *Scheduler) !void {
        if (!self.gpu.inFlight()) return;
        try self.gpu.wait(self.io);
        self.reportFrame();
    }

    fn reportFrame(self: *Scheduler) void {
        if (!self.profiling) return;
        if (self.in_flight_input.count != 0 and self.gpu.last_work_us == 0)
            std.log.info("UI input coalesced: events={d} unchanged", .{self.in_flight_input.count});
        if (self.in_flight_input.finish(self.render_started_us, @intCast(self.gpu.last_flip_us))) |sample| {
            const profile = self.gpu.last;
            std.log.info("UI input: events={d} oldest_to_flip={d}us newest_to_flip={d}us dispatch={d}us scene={d}us submit={d}us complete={d}us present={d}us flip={d}us collect={d}us target={d}us budget={d}us", .{
                sample.events,         sample.oldest_to_flip_us, sample.newest_to_flip_us, sample.dispatch_us,
                profile.scene_us,      profile.submit_us,        profile.complete_us,      profile.present_us,
                self.gpu.last_flip_us, sample.collection_us,     self.render_target_us,    self.render_budget_us,
            });
        } else if (self.gpu.last_flip_us != 0) {
            std.log.info("UI frame: flip={d}us work={d}us target={d}us budget={d}us", .{ self.gpu.last_flip_us, self.gpu.last_work_us, self.render_target_us, self.render_budget_us });
        }
    }
};

fn nowMicroseconds(io: std.Io) i64 {
    return std.Io.Timestamp.now(io, .awake).toMicroseconds();
}

fn writeAttribute(io: std.Io, path: []const u8, value: []const u8) !void {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only });
    defer file.close(io);
    var buffer: [32]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(value);
    try writer.interface.flush();
}

test "poll capacity includes the DRM completion descriptor" {
    try std.testing.expect(maximum_poll_fds > 1);
}
