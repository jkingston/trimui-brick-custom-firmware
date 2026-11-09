// SPDX-License-Identifier: GPL-2.0-only
// Bounded, opt-in test presenter. The caller stops/restarts the shell service.
const std = @import("std");
const Mode = extern struct {
    clock: u32,
    hdisplay: u16,
    hsync_start: u16,
    hsync_end: u16,
    htotal: u16,
    hskew: u16,
    vdisplay: u16,
    vsync_start: u16,
    vsync_end: u16,
    vtotal: u16,
    vscan: u16,
    vrefresh: u32,
    flags: u32,
    kind: u32,
    name: [32]u8,
};
const Crtc = extern struct { id: u32, buffer: u32, x: u32, y: u32, width: u32, height: u32, valid: c_int, mode: Mode, gamma: c_int };
const Resources = extern struct {
    fb_count: c_int,
    fbs: [*]u32,
    crtc_count: c_int,
    crtcs: [*]u32,
    connector_count: c_int,
    connectors: [*]u32,
    encoder_count: c_int,
    encoders: [*]u32,
    min_width: u32,
    max_width: u32,
    min_height: u32,
    max_height: u32,
};
const Connector = extern struct {
    id: u32,
    encoder: u32,
    kind: u32,
    kind_id: u32,
    connection: c_int,
    mm_width: u32,
    mm_height: u32,
    subpixel: c_int,
    mode_count: c_int,
    modes: ?*anyopaque,
    prop_count: c_int,
    props: ?*anyopaque,
    prop_values: ?*anyopaque,
    encoder_count: c_int,
    encoders: ?*anyopaque,
};
const Encoder = extern struct { id: u32, kind: u32, crtc: u32, possible_crtcs: u32, possible_clones: u32 };
const Handler = ?*const fn (c_int, c_uint, c_uint, c_uint, ?*anyopaque) callconv(.c) void;
const Events = extern struct { version: c_int = 2, vblank: Handler = null, flip: Handler = flipped, flip2: ?*anyopaque = null, sequence: ?*anyopaque = null };
const Poll = extern struct { fd: c_int, events: c_short, revents: c_short = 0 };
extern "c" fn poll([*]Poll, c_ulong, c_int) c_int;
extern "drm" fn drmModeGetResources(c_int) ?*Resources;
extern "drm" fn drmModeFreeResources(*Resources) void;
extern "drm" fn drmModeGetConnector(c_int, u32) ?*Connector;
extern "drm" fn drmModeFreeConnector(*Connector) void;
extern "drm" fn drmModeGetEncoder(c_int, u32) ?*Encoder;
extern "drm" fn drmModeFreeEncoder(*Encoder) void;
extern "drm" fn drmModeGetCrtc(c_int, u32) ?*Crtc;
extern "drm" fn drmModeFreeCrtc(*Crtc) void;
extern "drm" fn drmModeSetCrtc(c_int, u32, u32, u32, u32, [*]const u32, c_int, *const Mode) c_int;
extern "drm" fn drmSetMaster(c_int) c_int;
extern "drm" fn drmDropMaster(c_int) c_int;
extern "drm" fn drmModeAddFB(c_int, u32, u32, u8, u8, u32, u32, *u32) c_int;
extern "drm" fn drmModeRmFB(c_int, u32) c_int;
extern "drm" fn drmModePageFlip(c_int, u32, u32, u32, ?*anyopaque) c_int;
extern "drm" fn drmHandleEvent(c_int, *Events) c_int;

const Completion = struct { done: bool = false, sequence: u32 = 0, timestamp_us: u64 = 0 };
fn flipped(_: c_int, seq: c_uint, sec: c_uint, usec: c_uint, data: ?*anyopaque) callconv(.c) void {
    const result: *Completion = @ptrCast(@alignCast(data.?));
    result.* = .{ .done = true, .sequence = seq, .timestamp_us = @as(u64, sec) * 1_000_000 + usec };
}

pub const Presenter = struct {
    fd: c_int,
    saved: Crtc,
    connector: u32,
    buffers: [2]u32 = .{ 0, 0 },
    changed: bool = false,
    pub fn init(fd: c_int, handles: [2]u32, pitches: [2]u32) !Presenter {
        if (drmSetMaster(fd) != 0) return error.DrmMaster;
        errdefer _ = drmDropMaster(fd);
        const resources = drmModeGetResources(fd) orelse return error.DrmResources;
        defer drmModeFreeResources(resources);
        // This experiment deliberately refuses multi-connector configurations.
        if (resources.connector_count != 1) return error.UnsupportedDisplay;
        const connector = drmModeGetConnector(fd, resources.connectors[0]) orelse return error.DrmConnector;
        defer drmModeFreeConnector(connector);
        if (connector.connection != 1 or connector.encoder == 0) return error.Disconnected;
        const encoder = drmModeGetEncoder(fd, connector.encoder) orelse return error.DrmEncoder;
        defer drmModeFreeEncoder(encoder);
        const crtc = drmModeGetCrtc(fd, encoder.crtc) orelse return error.DrmCrtc;
        defer drmModeFreeCrtc(crtc);
        if (crtc.valid == 0 or crtc.buffer == 0 or crtc.mode.hdisplay != 1024 or crtc.mode.vdisplay != 768) return error.UnsupportedMode;
        var self = Presenter{ .fd = fd, .saved = crtc.*, .connector = connector.id };
        errdefer self.deinit();
        for (0..2) |i| if (drmModeAddFB(fd, 1024, 768, 24, 32, pitches[i], handles[i], &self.buffers[i]) != 0) return error.DrmAddFb;
        return self;
    }
    pub fn start(self: *Presenter) !void {
        if (drmModeSetCrtc(self.fd, self.saved.id, self.buffers[0], 0, 0, &.{self.connector}, 1, &self.saved.mode) != 0) return error.DrmModeset;
        self.changed = true;
    }
    pub fn present(self: *Presenter, index: usize) !u64 {
        var completion: Completion = .{};
        if (drmModePageFlip(self.fd, self.saved.id, self.buffers[index], 1, &completion) != 0) return error.DrmFlip;
        var fds = [_]Poll{.{ .fd = self.fd, .events = 1 }};
        var events: Events = .{};
        if (poll(&fds, 1, 2000) != 1 or (fds[0].revents & 1) == 0) return error.DrmFlipTimeout;
        if (drmHandleEvent(self.fd, &events) != 0 or !completion.done) return error.DrmFlipEvent;
        return completion.timestamp_us;
    }
    pub fn restore(self: *Presenter) !void {
        if (!self.changed) return;
        if (drmModeSetCrtc(self.fd, self.saved.id, self.saved.buffer, self.saved.x, self.saved.y, &.{self.connector}, 1, &self.saved.mode) != 0) return error.DrmRestore;
        self.changed = false;
        std.debug.print("PASS: original KMS state restored\n", .{});
    }
    pub fn deinit(self: *Presenter) void {
        self.restore() catch {
            std.debug.print("FAIL: original KMS state restoration; watchdog recovery required\n", .{});
        };
        for (self.buffers) |fb| if (fb != 0) {
            _ = drmModeRmFB(self.fd, fb);
        };
        _ = drmDropMaster(self.fd);
    }
};
