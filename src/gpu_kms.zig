// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const ui = @import("ui_scene.zig");
pub const buffer_count = 3;

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
const Framebuffer = extern struct { id: u32, width: u32, height: u32, pitch: u32, bpp: u32, depth: u32, handle: u32 };
const PlaneResources = extern struct { count: u32, planes: [*]u32 };
const Plane = extern struct {
    format_count: u32,
    formats: [*]u32,
    id: u32,
    crtc: u32,
    framebuffer: u32,
    crtc_x: u32,
    crtc_y: u32,
    x: u32,
    y: u32,
    possible_crtcs: u32,
    gamma_size: u32,
};
const ObjectProperties = extern struct { count: u32, ids: [*]u32, values: [*]u64 };
const Property = extern struct {
    id: u32,
    flags: u32,
    name: [32]u8,
    value_count: c_int,
    values: [*]u64,
    enum_count: c_int,
    enums: ?*anyopaque,
    blob_count: c_int,
    blob_ids: [*]u32,
};
const AtomicRequest = opaque {};
const Handler = ?*const fn (c_int, c_uint, c_uint, c_uint, ?*anyopaque) callconv(.c) void;
const Events = extern struct { version: c_int = 2, vblank: Handler = null, flip: Handler = flipped, flip2: ?*anyopaque = null, sequence: ?*anyopaque = null };
const Poll = extern struct { fd: c_int, events: c_short, revents: c_short = 0 };
extern "c" fn poll([*]Poll, c_ulong, c_int) c_int;

const PlaneProperties = struct {
    framebuffer: u32 = 0,
    crtc: u32 = 0,
    crtc_x: u32 = 0,
    crtc_y: u32 = 0,
    crtc_w: u32 = 0,
    crtc_h: u32 = 0,
    src_x: u32 = 0,
    src_y: u32 = 0,
    src_w: u32 = 0,
    src_h: u32 = 0,
};

const Api = struct {
    drmModeGetResources: *const fn (c_int) callconv(.c) ?*Resources,
    drmModeFreeResources: *const fn (*Resources) callconv(.c) void,
    drmModeGetConnector: *const fn (c_int, u32) callconv(.c) ?*Connector,
    drmModeFreeConnector: *const fn (*Connector) callconv(.c) void,
    drmModeGetEncoder: *const fn (c_int, u32) callconv(.c) ?*Encoder,
    drmModeFreeEncoder: *const fn (*Encoder) callconv(.c) void,
    drmModeGetCrtc: *const fn (c_int, u32) callconv(.c) ?*Crtc,
    drmModeFreeCrtc: *const fn (*Crtc) callconv(.c) void,
    drmModeSetCrtc: *const fn (c_int, u32, u32, u32, u32, [*]const u32, c_int, *const Mode) callconv(.c) c_int,
    drmModeGetFB: *const fn (c_int, u32) callconv(.c) ?*Framebuffer,
    drmModeFreeFB: *const fn (*Framebuffer) callconv(.c) void,
    drmSetClientCap: *const fn (c_int, u64, u64) callconv(.c) c_int,
    drmSetMaster: *const fn (c_int) callconv(.c) c_int,
    drmDropMaster: *const fn (c_int) callconv(.c) c_int,
    drmModeAddFB: *const fn (c_int, u32, u32, u8, u8, u32, u32, *u32) callconv(.c) c_int,
    drmModeAddFB2: *const fn (c_int, u32, u32, u32, [*]const u32, [*]const u32, [*]const u32, *u32, u32) callconv(.c) c_int,
    drmModeRmFB: *const fn (c_int, u32) callconv(.c) c_int,
    drmModeGetPlaneResources: *const fn (c_int) callconv(.c) ?*PlaneResources,
    drmModeFreePlaneResources: *const fn (*PlaneResources) callconv(.c) void,
    drmModeGetPlane: *const fn (c_int, u32) callconv(.c) ?*Plane,
    drmModeFreePlane: *const fn (*Plane) callconv(.c) void,
    drmModeObjectGetProperties: *const fn (c_int, u32, u32) callconv(.c) ?*ObjectProperties,
    drmModeFreeObjectProperties: *const fn (*ObjectProperties) callconv(.c) void,
    drmModeGetProperty: *const fn (c_int, u32) callconv(.c) ?*Property,
    drmModeFreeProperty: *const fn (*Property) callconv(.c) void,
    drmModeAtomicAlloc: *const fn () callconv(.c) ?*AtomicRequest,
    drmModeAtomicFree: *const fn (*AtomicRequest) callconv(.c) void,
    drmModeAtomicAddProperty: *const fn (*AtomicRequest, u32, u32, u64) callconv(.c) c_int,
    drmModeAtomicCommit: *const fn (c_int, *AtomicRequest, u32, ?*anyopaque) callconv(.c) c_int,
    drmHandleEvent: *const fn (c_int, *Events) callconv(.c) c_int,
    drmCrtcGetSequence: *const fn (c_int, u32, *u64, *u64) callconv(.c) c_int,
};
// SAFETY: load fills every entry before a Presenter is constructed.
var api: Api = undefined;
var library: ?std.DynLib = null;

fn load() !void {
    if (library != null) return;
    var opened = try std.DynLib.open("libdrm.so.2");
    errdefer opened.close();
    inline for (@typeInfo(Api).@"struct".field_names) |name|
        @field(api, name) = opened.lookup(@FieldType(Api, name), name) orelse return error.MissingDrmSymbol;
    library = opened;
}

const Completion = struct { done: bool = false, timestamp_us: u64 = 0 };
fn flipped(_: c_int, _: c_uint, sec: c_uint, usec: c_uint, data: ?*anyopaque) callconv(.c) void {
    const completion: *Completion = @ptrCast(@alignCast(data.?));
    completion.* = .{ .done = true, .timestamp_us = @as(u64, sec) * 1_000_000 + usec };
}

fn propertyName(property: *const Property) []const u8 {
    return std.mem.sliceTo(&property.name, 0);
}

fn properties(fd: c_int, plane_id: u32) !PlaneProperties {
    const list = api.drmModeObjectGetProperties(fd, plane_id, 0xeeeeeeee) orelse return error.DrmProperties;
    defer api.drmModeFreeObjectProperties(list);
    var result: PlaneProperties = .{};
    for (list.ids[0..list.count]) |id| {
        const property = api.drmModeGetProperty(fd, id) orelse return error.DrmProperty;
        defer api.drmModeFreeProperty(property);
        const name = propertyName(property);
        if (std.mem.eql(u8, name, "FB_ID")) result.framebuffer = id;
        if (std.mem.eql(u8, name, "CRTC_ID")) result.crtc = id;
        if (std.mem.eql(u8, name, "CRTC_X")) result.crtc_x = id;
        if (std.mem.eql(u8, name, "CRTC_Y")) result.crtc_y = id;
        if (std.mem.eql(u8, name, "CRTC_W")) result.crtc_w = id;
        if (std.mem.eql(u8, name, "CRTC_H")) result.crtc_h = id;
        if (std.mem.eql(u8, name, "SRC_X")) result.src_x = id;
        if (std.mem.eql(u8, name, "SRC_Y")) result.src_y = id;
        if (std.mem.eql(u8, name, "SRC_W")) result.src_w = id;
        if (std.mem.eql(u8, name, "SRC_H")) result.src_h = id;
    }
    if (result.framebuffer == 0 or result.crtc == 0) return error.DrmRequiredProperties;
    return result;
}

fn planeType(fd: c_int, plane_id: u32) !?u64 {
    const list = api.drmModeObjectGetProperties(fd, plane_id, 0xeeeeeeee) orelse return error.DrmProperties;
    defer api.drmModeFreeObjectProperties(list);
    for (list.ids[0..list.count], list.values[0..list.count]) |id, value| {
        const property = api.drmModeGetProperty(fd, id) orelse return error.DrmProperty;
        defer api.drmModeFreeProperty(property);
        if (std.mem.eql(u8, propertyName(property), "type")) return value;
    }
    return null;
}

fn usableCrtc(crtc: *const Crtc) bool {
    // Atomic DRM clients can leave a valid mode with no legacy CRTC buffer.
    // The next owner can still modeset its own primary plane in that mode.
    return crtc.valid != 0 and crtc.mode.hdisplay == 1024 and crtc.mode.vdisplay == 768;
}

fn isHandoffFramebuffer(framebuffer: *const Framebuffer) bool {
    // fbdev has a three-page virtual surface, so its DRM framebuffer is taller
    // than the active mode. It remains kernel-owned across UI and game clients.
    return framebuffer.width == 1024 and framebuffer.height >= 768;
}

fn handoffFramebuffer(fd: c_int, resources: *const Resources) !u32 {
    var result: u32 = 0;
    for (resources.fbs[0..@intCast(resources.fb_count)]) |id| {
        const framebuffer = api.drmModeGetFB(fd, id) orelse return error.DrmFramebuffer;
        defer api.drmModeFreeFB(framebuffer);
        if (!isHandoffFramebuffer(framebuffer)) continue;
        if (result != 0) return error.AmbiguousHandoffFramebuffer;
        result = id;
    }
    return if (result != 0) result else error.MissingHandoffFramebuffer;
}

fn add(request: *AtomicRequest, object: u32, property: u32, value: u64) !void {
    if (property == 0 or api.drmModeAtomicAddProperty(request, object, property, value) < 0) return error.DrmAtomicProperty;
}

pub const Presenter = struct {
    fd: c_int,
    saved: Crtc,
    connector: u32,
    primary_plane: u32,
    primary: PlaneProperties,
    overlay_plane: u32,
    overlay: PlaneProperties,
    buffers: [buffer_count]u32 = @splat(0),
    overlays: [buffer_count]u32 = @splat(0),
    changed: bool = false,
    completion: Completion = .{},
    pending: bool = false,
    io: ?std.Io = null,
    deadline_us: i64 = 0,

    pub fn init(fd: c_int, handles: [buffer_count]u32, pitches: [buffer_count]u32, overlay_handles: [buffer_count]u32, overlay_pitches: [buffer_count]u32) !Presenter {
        try load();
        if (api.drmSetMaster(fd) != 0) return error.DrmMaster;
        errdefer _ = api.drmDropMaster(fd);
        if (api.drmSetClientCap(fd, 2, 1) != 0 or api.drmSetClientCap(fd, 3, 1) != 0) return error.DrmAtomicCapability;
        const resources = api.drmModeGetResources(fd) orelse return error.DrmResources;
        defer api.drmModeFreeResources(resources);
        if (resources.connector_count != 1 or resources.crtc_count != 1) return error.UnsupportedDisplay;
        const connector = api.drmModeGetConnector(fd, resources.connectors[0]) orelse return error.DrmConnector;
        defer api.drmModeFreeConnector(connector);
        if (connector.connection != 1 or connector.encoder == 0) return error.Disconnected;
        const encoder = api.drmModeGetEncoder(fd, connector.encoder) orelse return error.DrmEncoder;
        defer api.drmModeFreeEncoder(encoder);
        const crtc = api.drmModeGetCrtc(fd, encoder.crtc) orelse return error.DrmCrtc;
        defer api.drmModeFreeCrtc(crtc);
        if (!usableCrtc(crtc)) return error.UnsupportedMode;
        var saved = crtc.*;
        if (saved.buffer == 0) {
            // RetroArch's atomic DRM backend removes its plane framebuffer on
            // exit, so drmModeGetCrtc reports buffer 0 even though the mode is
            // still valid. Restore the persistent fbdev framebuffer between
            // owners; otherwise closing this UI session would disable the CRTC
            // and the next menu/overlay could not reacquire it.
            saved.buffer = try handoffFramebuffer(fd, resources);
        }
        const planes = api.drmModeGetPlaneResources(fd) orelse return error.DrmPlanes;
        defer api.drmModeFreePlaneResources(planes);
        var primary_plane: u32 = 0;
        var overlay_plane: u32 = 0;
        for (planes.planes[0..planes.count]) |plane_id| {
            const plane = api.drmModeGetPlane(fd, plane_id) orelse return error.DrmPlane;
            defer api.drmModeFreePlane(plane);
            const kind = try planeType(fd, plane_id);
            // Prefer the legacy scanout match when one exists. RetroArch uses
            // atomic planes and removes its framebuffer on exit, leaving
            // crtc.buffer at zero; in that state use the kernel's immutable
            // primary-plane type instead.
            if ((crtc.buffer != 0 and plane.crtc == crtc.id and plane.framebuffer == crtc.buffer) or
                (primary_plane == 0 and kind == 1 and plane.possible_crtcs & 1 != 0))
                primary_plane = plane.id;
            if (plane.crtc == 0 and kind != 1 and std.mem.indexOfScalar(u32, plane.formats[0..plane.format_count], 0x34325241) != null) overlay_plane = plane.id;
        }
        if (primary_plane == 0 or overlay_plane == 0) return error.DrmCompositionPlanes;
        var self = Presenter{
            .fd = fd,
            .saved = saved,
            .connector = connector.id,
            .primary_plane = primary_plane,
            .primary = try properties(fd, primary_plane),
            .overlay_plane = overlay_plane,
            .overlay = try properties(fd, overlay_plane),
        };
        errdefer self.deinit();
        for (0..buffer_count) |index| {
            if (api.drmModeAddFB(fd, 1024, 768, 24, 32, pitches[index], handles[index], &self.buffers[index]) != 0) return error.DrmAddFb;
            const objects = [4]u32{ overlay_handles[index], 0, 0, 0 };
            const strides = [4]u32{ overlay_pitches[index], 0, 0, 0 };
            const offsets = [4]u32{ 0, 0, 0, 0 };
            if (api.drmModeAddFB2(fd, 1024, 768, 0x34325241, &objects, &strides, &offsets, &self.overlays[index], 0) != 0) return error.DrmAddOverlayFb;
        }
        return self;
    }

    fn compose(self: *Presenter, base_index: usize, overlay_index: usize, selection: ?ui.Rect, flags: u32, data: ?*anyopaque) !void {
        const request = api.drmModeAtomicAlloc() orelse return error.DrmAtomicAlloc;
        defer api.drmModeAtomicFree(request);
        try add(request, self.primary_plane, self.primary.framebuffer, self.buffers[base_index]);
        if (selection != null) {
            try add(request, self.overlay_plane, self.overlay.framebuffer, self.overlays[overlay_index]);
            try add(request, self.overlay_plane, self.overlay.crtc, self.saved.id);
            // The A133 display engine visibly tears when UI layer geometry is
            // changed before the old layer's final scanline has retired. Keep
            // the plane geometry immutable and express selection changes only
            // through transparent full-screen ARGB framebuffer flips.
            try add(request, self.overlay_plane, self.overlay.crtc_x, 0);
            try add(request, self.overlay_plane, self.overlay.crtc_y, 0);
            try add(request, self.overlay_plane, self.overlay.crtc_w, 1024);
            try add(request, self.overlay_plane, self.overlay.crtc_h, 768);
            try add(request, self.overlay_plane, self.overlay.src_x, 0);
            try add(request, self.overlay_plane, self.overlay.src_y, 0);
            try add(request, self.overlay_plane, self.overlay.src_w, 1024 << 16);
            try add(request, self.overlay_plane, self.overlay.src_h, 768 << 16);
        } else {
            try add(request, self.overlay_plane, self.overlay.framebuffer, 0);
            try add(request, self.overlay_plane, self.overlay.crtc, 0);
        }
        if (api.drmModeAtomicCommit(self.fd, request, flags, data) != 0) return error.DrmAtomicCommit;
    }

    pub fn start(self: *Presenter, base_index: usize, overlay_index: usize, selection: ?ui.Rect) !void {
        if (api.drmModeSetCrtc(self.fd, self.saved.id, self.buffers[base_index], 0, 0, &.{self.connector}, 1, &self.saved.mode) != 0) return error.DrmModeset;
        self.changed = true;
        try self.compose(base_index, overlay_index, selection, 0, null);
    }

    pub fn queue(self: *Presenter, io: std.Io, base_index: usize, overlay_index: usize, selection: ?ui.Rect) !void {
        if (self.pending) return error.FramePending;
        self.completion = .{};
        try self.compose(base_index, overlay_index, selection, 0x0201, &self.completion);
        self.pending = true;
        self.io = io;
        self.deadline_us = std.Io.Timestamp.now(io, .awake).toMicroseconds() + 2_000_000;
    }

    pub fn timing(self: *Presenter) !struct { vblank_us: i64, period_us: i64 } {
        var sequence: u64 = 0;
        var timestamp_ns: u64 = 0;
        if (api.drmCrtcGetSequence(self.fd, self.saved.id, &sequence, &timestamp_ns) != 0) return error.DrmSequence;
        const period_us = @as(u64, self.saved.mode.htotal) * self.saved.mode.vtotal * 1000 / self.saved.mode.clock;
        if (period_us == 0) return error.InvalidRefreshPeriod;
        return .{ .vblank_us = @intCast(timestamp_ns / 1000), .period_us = @intCast(period_us) };
    }

    pub fn remainingUs(self: *Presenter) !i64 {
        if (!self.pending) return error.NoPendingFrame;
        const remaining = self.deadline_us - std.Io.Timestamp.now(self.io.?, .awake).toMicroseconds();
        if (remaining <= 0) return error.DrmFlipTimeout;
        return remaining;
    }

    pub fn dispatch(self: *Presenter) !?u64 {
        if (!self.pending) return error.NoPendingFrame;
        var events: Events = .{};
        if (api.drmHandleEvent(self.fd, &events) != 0) return error.DrmFlipEvent;
        if (!self.completion.done) return null;
        self.pending = false;
        return self.completion.timestamp_us;
    }

    pub fn wait(self: *Presenter) !u64 {
        var descriptors = [_]Poll{.{ .fd = self.fd, .events = 1 }};
        while (true) {
            const result = poll(&descriptors, 1, @intCast(@divTrunc(try self.remainingUs() + 999, 1000)));
            if (result < 0 and @import("gpu_abi.zig").__errno_location().* == 4) continue;
            if (result == 0) return error.DrmFlipTimeout;
            if (result < 0 or (descriptors[0].revents & 1) == 0) return error.DrmFlipPoll;
            if (try self.dispatch()) |timestamp| return timestamp;
        }
    }

    fn disableOverlay(self: *Presenter) !void {
        const request = api.drmModeAtomicAlloc() orelse return error.DrmAtomicAlloc;
        defer api.drmModeAtomicFree(request);
        try add(request, self.overlay_plane, self.overlay.framebuffer, 0);
        try add(request, self.overlay_plane, self.overlay.crtc, 0);
        if (api.drmModeAtomicCommit(self.fd, request, 0, null) != 0) return error.DrmOverlayDisable;
    }

    pub fn restore(self: *Presenter) !void {
        if (!self.changed) return;
        try self.disableOverlay();
        if (api.drmModeSetCrtc(self.fd, self.saved.id, self.saved.buffer, self.saved.x, self.saved.y, &.{self.connector}, 1, &self.saved.mode) != 0) return error.DrmRestore;
        self.changed = false;
        std.log.info("PASS: original KMS state restored", .{});
    }

    pub fn deinit(self: *Presenter) void {
        if (self.pending) _ = self.wait() catch 0;
        self.restore() catch std.log.err("original KMS state restoration failed", .{});
        for (self.overlays) |framebuffer| {
            if (framebuffer != 0) _ = api.drmModeRmFB(self.fd, framebuffer);
        }
        for (self.buffers) |framebuffer| {
            if (framebuffer != 0) _ = api.drmModeRmFB(self.fd, framebuffer);
        }
        _ = api.drmDropMaster(self.fd);
    }
};

test "an atomic client may hand off a valid mode without a legacy framebuffer" {
    var crtc: Crtc = std.mem.zeroes(Crtc);
    crtc.valid = 1;
    crtc.mode.hdisplay = 1024;
    crtc.mode.vdisplay = 768;
    try std.testing.expectEqual(@as(u32, 0), crtc.buffer);
    try std.testing.expect(usableCrtc(&crtc));

    var framebuffer: Framebuffer = std.mem.zeroes(Framebuffer);
    framebuffer.width = 1024;
    framebuffer.height = 2304;
    try std.testing.expect(isHandoffFramebuffer(&framebuffer));
}
