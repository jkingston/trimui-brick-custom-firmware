// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

const PlaneResources = extern struct {
    count: u32,
    planes: [*]u32,
};

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

const ObjectProperties = extern struct {
    count: u32,
    ids: [*]u32,
    values: [*]u64,
};

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
const DumbBuffer = extern struct {
    height: u32,
    width: u32,
    bpp: u32,
    flags: u32,
    handle: u32,
    pitch: u32,
    size: u64,
};
const DestroyDumb = extern struct { handle: u32 };
const MapDumb = extern struct { handle: u32, padding: u32 = 0, offset: u64 = 0 };
const Handler = ?*const fn (c_int, c_uint, c_uint, c_uint, ?*anyopaque) callconv(.c) void;
const Events = extern struct {
    version: c_int = 2,
    vblank: Handler = null,
    flip: Handler = flipped,
    flip2: ?*anyopaque = null,
    sequence: ?*anyopaque = null,
};
const Poll = extern struct { fd: c_int, events: c_short, revents: c_short = 0 };
const Completion = struct { done: bool = false };

fn flipped(_: c_int, _: c_uint, _: c_uint, _: c_uint, data: ?*anyopaque) callconv(.c) void {
    const completion: *Completion = @ptrCast(@alignCast(data.?));
    completion.done = true;
}

extern "c" fn open([*:0]const u8, c_int, ...) c_int;
extern "c" fn close(c_int) c_int;
extern "c" fn __errno_location() *c_int;
extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;
extern "c" fn ioctl(c_int, c_ulong, ...) c_int;
extern "c" fn mmap(?*anyopaque, usize, c_int, c_int, c_int, i64) ?*anyopaque;
extern "c" fn munmap(?*anyopaque, usize) c_int;
extern "c" fn usleep(c_uint) c_int;
extern "c" fn poll([*]Poll, c_ulong, c_int) c_int;
extern "drm" fn drmSetClientCap(c_int, u64, u64) c_int;
extern "drm" fn drmSetMaster(c_int) c_int;
extern "drm" fn drmDropMaster(c_int) c_int;
extern "drm" fn drmModeGetPlaneResources(c_int) ?*PlaneResources;
extern "drm" fn drmModeFreePlaneResources(*PlaneResources) void;
extern "drm" fn drmModeGetPlane(c_int, u32) ?*Plane;
extern "drm" fn drmModeFreePlane(*Plane) void;
extern "drm" fn drmModeObjectGetProperties(c_int, u32, u32) ?*ObjectProperties;
extern "drm" fn drmModeFreeObjectProperties(*ObjectProperties) void;
extern "drm" fn drmModeGetProperty(c_int, u32) ?*Property;
extern "drm" fn drmModeFreeProperty(*Property) void;
extern "drm" fn drmModeAtomicAlloc() ?*AtomicRequest;
extern "drm" fn drmModeAtomicFree(*AtomicRequest) void;
extern "drm" fn drmModeAtomicAddProperty(*AtomicRequest, u32, u32, u64) c_int;
extern "drm" fn drmModeAtomicCommit(c_int, *AtomicRequest, u32, ?*anyopaque) c_int;
extern "drm" fn drmModeAddFB2(c_int, u32, u32, u32, [*]const u32, [*]const u32, [*]const u32, *u32, u32) c_int;
extern "drm" fn drmModeRmFB(c_int, u32) c_int;
extern "drm" fn drmHandleEvent(c_int, *Events) c_int;

const object_plane: u32 = 0xeeeeeeee;
const client_universal_planes: u64 = 2;
const client_atomic: u64 = 3;
const atomic_test_only: u32 = 0x0100;
const open_read_write: c_int = 2;
const open_cloexec: c_int = 0x80000;
const ioctl_create_dumb: c_ulong = 0xc02064b2;
const ioctl_map_dumb: c_ulong = 0xc01064b3;
const ioctl_destroy_dumb: c_ulong = 0xc00464b4;
const format_argb8888: u32 = 0x34325241;
const format_xrgb8888: u32 = 0x34325258;
const atomic_page_flip_event: u32 = 0x0001;
const atomic_nonblock: u32 = 0x0200;
const map_failed: ?*anyopaque = @ptrFromInt(~@as(usize, 0));
const overlay_width: u32 = 384;
const overlay_height: u32 = 128;

const DsiDebug = struct {
    fd: c_int,
    memory: *anyopaque,

    fn openDebug() ?DsiDebug {
        const fd = open("/dev/mem", open_cloexec);
        if (fd < 0) return null;
        const memory = mmap(null, 4096, 1, 1, fd, 0x06504000);
        if (memory == null or memory == map_failed) {
            _ = close(fd);
            return null;
        }
        return .{ .fd = fd, .memory = memory.? };
    }

    fn currentLine(self: *const DsiDebug) u32 {
        const register: *volatile u32 = @ptrFromInt(@intFromPtr(self.memory) + 0x2e0);
        return register.* & 0x1fff;
    }

    fn closeDebug(self: *DsiDebug) void {
        _ = munmap(self.memory, 4096);
        _ = close(self.fd);
    }
};

const TestBuffer = struct {
    dumb: DumbBuffer = std.mem.zeroes(DumbBuffer),
    memory: ?*anyopaque = null,
    framebuffer: u32 = 0,

    fn init(fd: c_int, width: u32, height: u32, format: u32) !TestBuffer {
        var self: TestBuffer = .{};
        self.dumb.width = width;
        self.dumb.height = height;
        self.dumb.bpp = 32;
        if (ioctl(fd, ioctl_create_dumb, &self.dumb) != 0) return error.CreateDumb;
        errdefer self.deinit(fd);
        var map: MapDumb = .{ .handle = self.dumb.handle };
        if (ioctl(fd, ioctl_map_dumb, &map) != 0) return error.MapDumb;
        self.memory = mmap(null, @intCast(self.dumb.size), 3, 1, fd, @intCast(map.offset));
        if (self.memory == null or self.memory == map_failed) return error.MapMemory;
        const handles = [4]u32{ self.dumb.handle, 0, 0, 0 };
        const pitches = [4]u32{ self.dumb.pitch, 0, 0, 0 };
        const offsets = [4]u32{ 0, 0, 0, 0 };
        if (drmModeAddFB2(fd, width, height, format, &handles, &pitches, &offsets, &self.framebuffer, 0) != 0) return error.AddFramebuffer;
        return self;
    }

    fn fill(self: *TestBuffer, color: u32) void {
        const pixels: [*]u32 = @ptrCast(@alignCast(self.memory.?));
        const stride = self.dumb.pitch / 4;
        for (0..self.dumb.height) |y| @memset(pixels[y * stride ..][0..self.dumb.width], color);
    }

    fn fillBars(self: *TestBuffer, first: u32, second: u32) void {
        const pixels: [*]u32 = @ptrCast(@alignCast(self.memory.?));
        const stride = self.dumb.pitch / 4;
        for (0..self.dumb.height) |y| {
            const color = if ((y / 32) % 2 == 0) first else second;
            @memset(pixels[y * stride ..][0..self.dumb.width], color);
        }
    }

    fn deinit(self: *TestBuffer, fd: c_int) void {
        if (self.framebuffer != 0) _ = drmModeRmFB(fd, self.framebuffer);
        if (self.memory != null and self.memory != map_failed) _ = munmap(self.memory, @intCast(self.dumb.size));
        if (self.dumb.handle != 0) {
            var destroy = DestroyDumb{ .handle = self.dumb.handle };
            _ = ioctl(fd, ioctl_destroy_dumb, &destroy);
        }
        self.* = .{};
    }
};

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

    fn complete(self: PlaneProperties) bool {
        return self.framebuffer != 0 and self.crtc != 0 and self.crtc_x != 0 and self.crtc_y != 0 and
            self.crtc_w != 0 and self.crtc_h != 0 and self.src_x != 0 and self.src_y != 0 and
            self.src_w != 0 and self.src_h != 0;
    }
};

fn fourcc(value: u32) [4]u8 {
    return .{
        @truncate(value),
        @truncate(value >> 8),
        @truncate(value >> 16),
        @truncate(value >> 24),
    };
}

fn propertyName(property: *const Property) []const u8 {
    return std.mem.sliceTo(&property.name, 0);
}

fn printPlane(fd: c_int, id: u32) !void {
    const plane = drmModeGetPlane(fd, id) orelse return error.GetPlane;
    defer drmModeFreePlane(plane);
    std.debug.print("plane={d} crtc={d} fb={d} possible_crtcs=0x{x} formats=", .{
        plane.id,
        plane.crtc,
        plane.framebuffer,
        plane.possible_crtcs,
    });
    for (plane.formats[0..plane.format_count], 0..) |format, index| {
        if (index != 0) std.debug.print(",", .{});
        std.debug.print("{s}", .{fourcc(format)});
    }
    std.debug.print("\n", .{});

    const properties = drmModeObjectGetProperties(fd, id, object_plane) orelse return error.GetProperties;
    defer drmModeFreeObjectProperties(properties);
    for (properties.ids[0..properties.count], properties.values[0..properties.count]) |property_id, value| {
        const property = drmModeGetProperty(fd, property_id) orelse return error.GetProperty;
        defer drmModeFreeProperty(property);
        std.debug.print("  {s} id={d} value={d}\n", .{ propertyName(property), property_id, value });
    }
}

fn planeProperties(fd: c_int, plane_id: u32) !PlaneProperties {
    const properties = drmModeObjectGetProperties(fd, plane_id, object_plane) orelse return error.GetProperties;
    defer drmModeFreeObjectProperties(properties);
    var result: PlaneProperties = .{};
    for (properties.ids[0..properties.count]) |property_id| {
        const property = drmModeGetProperty(fd, property_id) orelse return error.GetProperty;
        defer drmModeFreeProperty(property);
        const name = propertyName(property);
        if (std.mem.eql(u8, name, "FB_ID")) result.framebuffer = property_id;
        if (std.mem.eql(u8, name, "CRTC_ID")) result.crtc = property_id;
        if (std.mem.eql(u8, name, "CRTC_X")) result.crtc_x = property_id;
        if (std.mem.eql(u8, name, "CRTC_Y")) result.crtc_y = property_id;
        if (std.mem.eql(u8, name, "CRTC_W")) result.crtc_w = property_id;
        if (std.mem.eql(u8, name, "CRTC_H")) result.crtc_h = property_id;
        if (std.mem.eql(u8, name, "SRC_X")) result.src_x = property_id;
        if (std.mem.eql(u8, name, "SRC_Y")) result.src_y = property_id;
        if (std.mem.eql(u8, name, "SRC_W")) result.src_w = property_id;
        if (std.mem.eql(u8, name, "SRC_H")) result.src_h = property_id;
    }
    if (!result.complete()) return error.IncompletePlaneProperties;
    return result;
}

fn addAtomic(request: *AtomicRequest, plane_id: u32, property_id: u32, value: u64) !void {
    if (drmModeAtomicAddProperty(request, plane_id, property_id, value) < 0) return error.AtomicAdd;
}

fn disableOverlay(fd: c_int, plane_id: u32, properties: PlaneProperties) !void {
    const request = drmModeAtomicAlloc() orelse return error.AtomicAlloc;
    defer drmModeAtomicFree(request);
    try addAtomic(request, plane_id, properties.framebuffer, 0);
    try addAtomic(request, plane_id, properties.crtc, 0);
    if (drmModeAtomicCommit(fd, request, 0, null) != 0) return error.DisableOverlay;
}

fn waitFlip(fd: c_int, completion: *Completion) !void {
    var descriptors = [_]Poll{.{ .fd = fd, .events = 1 }};
    var events: Events = .{};
    if (poll(&descriptors, 1, 2000) != 1 or (descriptors[0].revents & 1) == 0) return error.FlipTimeout;
    if (drmHandleEvent(fd, &events) != 0 or !completion.done) return error.FlipEvent;
}

fn commitFramebuffer(fd: c_int, plane_id: u32, property_id: u32, framebuffer: u32, nonblocking: bool) !void {
    const request = drmModeAtomicAlloc() orelse return error.AtomicAlloc;
    defer drmModeAtomicFree(request);
    try addAtomic(request, plane_id, property_id, framebuffer);
    if (nonblocking) {
        var completion: Completion = .{};
        if (drmModeAtomicCommit(fd, request, atomic_nonblock | atomic_page_flip_event, &completion) != 0) return error.PrimaryFlip;
        try waitFlip(fd, &completion);
    } else if (drmModeAtomicCommit(fd, request, 0, null) != 0) return error.PrimaryFlip;
}

fn reproFrames() !usize {
    return if (getenv("KMS_REPRO_FRAMES")) |value|
        try std.fmt.parseInt(usize, std.mem.span(value), 10)
    else
        120;
}

fn exerciseGeometryCase(fd: c_int, plane_id: u32, framebuffer: u32, properties: PlaneProperties, name: []const u8, frames: usize) !void {
    if (frames > 600) return error.TooManyReproFrames;
    const variable_scale = std.mem.eql(u8, name, "variable-scale");
    const unity = std.mem.eql(u8, name, "unity");
    const fixed_scale = std.mem.eql(u8, name, "fixed-scale");
    if (!variable_scale and !unity and !fixed_scale) return error.UnknownGeometryCase;
    const phase_us = if (getenv("KMS_GEOMETRY_PHASE_US")) |value|
        try std.fmt.parseInt(u32, std.mem.span(value), 10)
    else
        0;
    if (phase_us > 15_000) return error.InvalidGeometryPhase;
    const target_line: ?u32 = if (getenv("KMS_GEOMETRY_TARGET_LINE")) |value|
        try std.fmt.parseInt(u32, std.mem.span(value), 10)
    else
        null;
    if (target_line) |line| if (line > 782) return error.InvalidGeometryLine;

    var dsi_debug = DsiDebug.openDebug();
    defer if (dsi_debug) |*debug| debug.closeDebug();
    var contraction_min: u32 = std.math.maxInt(u32);
    var contraction_max: u32 = 0;
    var expansion_min: u32 = std.math.maxInt(u32);
    var expansion_max: u32 = 0;
    std.debug.print("GEOMETRY_CASE START name={s} frames={d} phase_us={d} target_line={any} first_direction=contraction\n", .{ name, frames, phase_us, target_line });
    for (0..frames) |index| {
        const phase = index % 240;
        const step = if (phase <= 120) 120 - phase else phase - 120;
        const destination_width: usize = if (fixed_scale) 96 + step * 96 / 120 else 192 + step * 192 / 120;
        const source_width: usize = if (variable_scale) overlay_width else if (unity) destination_width else destination_width * 2;
        if (target_line) |target| {
            const debug = if (dsi_debug) |*value| value else return error.ScanlineUnavailable;
            var attempts: usize = 0;
            while (true) {
                const line = debug.currentLine();
                if (line >= target and line <= target + 2) break;
                attempts += 1;
                if (attempts == 10_000_000) return error.ScanlineTimeout;
            }
        } else {
            _ = usleep(phase_us);
        }
        if (dsi_debug) |*debug| {
            const line = debug.currentLine();
            if (phase <= 120) {
                contraction_min = @min(contraction_min, line);
                contraction_max = @max(contraction_max, line);
            } else {
                expansion_min = @min(expansion_min, line);
                expansion_max = @max(expansion_max, line);
            }
        }
        const request = drmModeAtomicAlloc() orelse return error.AtomicAlloc;
        defer drmModeAtomicFree(request);
        try addAtomic(request, plane_id, properties.framebuffer, framebuffer);
        try addAtomic(request, plane_id, properties.crtc_w, destination_width);
        try addAtomic(request, plane_id, properties.src_w, source_width << 16);
        var completion: Completion = .{};
        if (drmModeAtomicCommit(fd, request, atomic_nonblock | atomic_page_flip_event, &completion) != 0) return error.GeometryCommit;
        try waitFlip(fd, &completion);
    }
    if (dsi_debug != null)
        std.debug.print("GEOMETRY_CASE END name={s} phase_us={d} target_line={any} contraction_line_min={d} contraction_line_max={d} expansion_line_min={d} expansion_line_max={d}\n", .{ name, phase_us, target_line, contraction_min, contraction_max, expansion_min, expansion_max })
    else
        std.debug.print("GEOMETRY_CASE END name={s} scanline=unavailable\n", .{name});
}

fn exercisePrimary(fd: c_int, resources: *const PlaneResources) !void {
    var primary_id: u32 = 0;
    var original_framebuffer: u32 = 0;
    for (resources.planes[0..resources.count]) |plane_id| {
        const plane = drmModeGetPlane(fd, plane_id) orelse return error.GetPlane;
        defer drmModeFreePlane(plane);
        if (plane.crtc != 0 and plane.framebuffer != 0) {
            primary_id = plane.id;
            original_framebuffer = plane.framebuffer;
            break;
        }
    }
    if (primary_id == 0) return error.NoPrimaryPlane;
    const properties = try planeProperties(fd, primary_id);
    var buffers = [3]TestBuffer{
        try TestBuffer.init(fd, 1024, 768, format_xrgb8888),
        try TestBuffer.init(fd, 1024, 768, format_xrgb8888),
        try TestBuffer.init(fd, 1024, 768, format_xrgb8888),
    };
    defer for (&buffers) |*buffer| buffer.deinit(fd);
    buffers[0].fillBars(0x00ff2020, 0x00601010);
    buffers[1].fillBars(0x0020ffff, 0x00106060);
    buffers[2].fillBars(0x00f0f0f0, 0x00202020);
    defer commitFramebuffer(fd, primary_id, properties.framebuffer, original_framebuffer, false) catch {
        std.debug.print("primary_restore=FAIL errno={d}\n", .{__errno_location().*});
    };

    const frames = try reproFrames();
    var dsi_debug = DsiDebug.openDebug();
    defer if (dsi_debug) |*debug| debug.closeDebug();
    std.debug.print("dsi_scanline_probe={s}\n", .{if (dsi_debug != null) "PASS register=0x065042e0" else "SKIP reason=/dev/mem-unavailable"});
    std.debug.print("REPRO primary_nonblock START frames={d} expected=clean alternating red/cyan bars\n", .{frames});
    for (0..frames) |frame| try commitFramebuffer(fd, primary_id, properties.framebuffer, buffers[frame % 2].framebuffer, true);
    std.debug.print("REPRO primary_nonblock END\n", .{});

    std.debug.print("REPRO primary_blocking START frames={d} expected=clean alternating red/cyan bars\n", .{frames});
    for (0..frames) |frame| {
        try commitFramebuffer(fd, primary_id, properties.framebuffer, buffers[frame % 2].framebuffer, false);
        _ = usleep(16_000);
    }
    std.debug.print("REPRO primary_blocking END\n", .{});

    const phases_us = [_]u32{ 0, 100, 250, 500, 1_000, 2_000, 4_000, 8_000, 12_000, 15_000 };
    const phase_frames = @max(@as(usize, 12), frames / phases_us.len);
    for (phases_us) |phase_us| {
        var minimum_line: u32 = std.math.maxInt(u32);
        var maximum_line: u32 = 0;
        std.debug.print("REPRO primary_phase START phase_us={d} frames={d}\n", .{ phase_us, phase_frames });
        for (0..phase_frames) |frame| {
            _ = usleep(phase_us);
            if (dsi_debug) |*debug| {
                const line = debug.currentLine();
                minimum_line = @min(minimum_line, line);
                maximum_line = @max(maximum_line, line);
            }
            try commitFramebuffer(fd, primary_id, properties.framebuffer, buffers[frame % 2].framebuffer, true);
        }
        if (dsi_debug != null)
            std.debug.print("REPRO primary_phase END phase_us={d} dsi_raw_line_min={d} dsi_raw_line_max={d}\n", .{ phase_us, minimum_line, maximum_line })
        else
            std.debug.print("REPRO primary_phase END phase_us={d}\n", .{phase_us});
    }

    const retirement_delays_us = [_]u32{ 0, 100, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000 };
    const retirement_frames = @max(@as(usize, 12), frames / retirement_delays_us.len);
    var front: usize = 0;
    try commitFramebuffer(fd, primary_id, properties.framebuffer, buffers[front].framebuffer, true);
    for (retirement_delays_us) |delay_us| {
        std.debug.print("REPRO retired_rewrite START delay_us={d} frames={d} expected=no flash or split from rewritten retired buffer\n", .{ delay_us, retirement_frames });
        for (0..retirement_frames) |frame| {
            const target = (front + 1) % 3;
            try commitFramebuffer(fd, primary_id, properties.framebuffer, buffers[target].framebuffer, true);
            _ = usleep(delay_us);
            buffers[front].fillBars(if (frame % 2 == 0) 0x00ff00ff else 0x0000ff00, 0x00000000);
            front = target;
        }
        std.debug.print("REPRO retired_rewrite END delay_us={d}\n", .{delay_us});
    }
    std.debug.print("primary_suite=PASS submission_and_event_integrity visual_result=REQUIRES_OBSERVATION\n", .{});
}

fn exerciseOverlay(io: std.Io, fd: c_int, plane_id: u32, crtc_id: u32, framebuffers: [2]u32, properties: PlaneProperties) !void {
    var enabled = false;
    defer if (enabled) disableOverlay(fd, plane_id, properties) catch {
        std.debug.print("overlay_disable=FAIL errno={d}\n", .{__errno_location().*});
    };

    const overlay_y = if (getenv("KMS_OVERLAY_Y")) |value|
        try std.fmt.parseInt(u32, std.mem.span(value), 10)
    else
        100;
    if (overlay_y + overlay_height > 768) return error.InvalidOverlayY;

    const enable = drmModeAtomicAlloc() orelse return error.AtomicAlloc;
    defer drmModeAtomicFree(enable);
    try addAtomic(enable, plane_id, properties.framebuffer, framebuffers[0]);
    try addAtomic(enable, plane_id, properties.crtc, crtc_id);
    try addAtomic(enable, plane_id, properties.crtc_x, 64);
    try addAtomic(enable, plane_id, properties.crtc_y, overlay_y);
    try addAtomic(enable, plane_id, properties.crtc_w, overlay_width);
    try addAtomic(enable, plane_id, properties.crtc_h, overlay_height);
    try addAtomic(enable, plane_id, properties.src_x, 0);
    try addAtomic(enable, plane_id, properties.src_y, 0);
    try addAtomic(enable, plane_id, properties.src_w, overlay_width << 16);
    try addAtomic(enable, plane_id, properties.src_h, overlay_height << 16);
    if (drmModeAtomicCommit(fd, enable, 0, null) != 0) return error.EnableOverlay;
    enabled = true;

    if (getenv("KMS_GEOMETRY_CASE")) |value| {
        const frames = try reproFrames();
        std.debug.print("GEOMETRY_LAYER y={d} height={d} final_line={d}\n", .{ overlay_y, overlay_height, overlay_y + overlay_height - 1 });
        try exerciseGeometryCase(fd, plane_id, framebuffers[0], properties, std.mem.span(value), frames);
        try disableOverlay(fd, plane_id, properties);
        enabled = false;
        return;
    }

    const sample_count = try reproFrames();
    const human_observation = getenv("KMS_HUMAN_OBSERVE") != null;
    const enable_only = getenv("KMS_HUMAN_ENABLE_ONLY") != null;
    if (sample_count > 600 or (!human_observation and sample_count > 120)) return error.TooManyReproFrames;
    var submit_us: [600]i64 = undefined;
    var present_us: [600]i64 = undefined;
    if (human_observation)
        std.debug.print("human_observation=ON smooth-motion slow-state-changes frames={d}\n", .{sample_count});
    if (!enable_only) {
        std.debug.print("REPRO overlay_position START frames={d} expected=opaque magenta/green rectangle moves cleanly\n", .{sample_count});
        for (0..sample_count) |index| {
            const request = drmModeAtomicAlloc() orelse return error.AtomicAlloc;
            defer drmModeAtomicFree(request);
            const position_phase = index % 240;
            const position_step = if (position_phase <= 120) position_phase else 240 - position_phase;
            const position: usize = if (human_observation) 64 + position_step * 512 / 120 else if (index % 2 == 0) 64 else 576;
            try addAtomic(request, plane_id, properties.crtc_x, position);
            var completion: Completion = .{};
            const started = std.Io.Timestamp.now(io, .awake);
            if (drmModeAtomicCommit(fd, request, atomic_nonblock | atomic_page_flip_event, &completion) != 0) return error.MoveOverlay;
            const submitted = std.Io.Timestamp.now(io, .awake);
            try waitFlip(fd, &completion);
            const presented = std.Io.Timestamp.now(io, .awake);
            submit_us[index] = started.durationTo(submitted).toMicroseconds();
            present_us[index] = started.durationTo(presented).toMicroseconds();
        }
        std.mem.sort(i64, submit_us[0..sample_count], {}, std.sort.asc(i64));
        std.mem.sort(i64, present_us[0..sample_count], {}, std.sort.asc(i64));
        std.debug.print("REPRO overlay_position END\n", .{});

        std.debug.print("REPRO overlay_framebuffer START frames={d} expected=stationary rectangle changes color without a split\n", .{sample_count});
        for (0..sample_count) |index| {
            const request = drmModeAtomicAlloc() orelse return error.AtomicAlloc;
            defer drmModeAtomicFree(request);
            try addAtomic(request, plane_id, properties.framebuffer, framebuffers[if (human_observation) (index / 30) % 2 else index % 2]);
            var completion: Completion = .{};
            if (drmModeAtomicCommit(fd, request, atomic_nonblock | atomic_page_flip_event, &completion) != 0) return error.SwapOverlay;
            try waitFlip(fd, &completion);
        }
        std.debug.print("REPRO overlay_framebuffer END\n", .{});

        std.debug.print("REPRO overlay_size START frames={d} expected=right edge changes width without horizontal tearing\n", .{sample_count});
        for (0..sample_count) |index| {
            const request = drmModeAtomicAlloc() orelse return error.AtomicAlloc;
            defer drmModeAtomicFree(request);
            const size_phase = index % 240;
            const size_step = if (size_phase <= 120) size_phase else 240 - size_phase;
            const width: usize = if (human_observation) overlay_width / 2 + size_step * (overlay_width / 2) / 120 else if (index % 2 == 0) overlay_width else overlay_width / 2;
            try addAtomic(request, plane_id, properties.crtc_w, width);
            var completion: Completion = .{};
            if (drmModeAtomicCommit(fd, request, atomic_nonblock | atomic_page_flip_event, &completion) != 0) return error.ResizeOverlay;
            try waitFlip(fd, &completion);
        }
        std.debug.print("REPRO overlay_size END\n", .{});
    }

    std.debug.print("REPRO overlay_enable START frames={d} expected=whole rectangle appears/disappears atomically\n", .{sample_count});
    var overlay_visible = true;
    for (0..sample_count) |index| {
        const visible = if (human_observation) (index / 30) % 2 != 0 else index % 2 != 0;
        if (human_observation and visible == overlay_visible) {
            _ = usleep(16_667);
            continue;
        }
        const request = drmModeAtomicAlloc() orelse return error.AtomicAlloc;
        defer drmModeAtomicFree(request);
        if (!visible) {
            try addAtomic(request, plane_id, properties.framebuffer, 0);
            try addAtomic(request, plane_id, properties.crtc, 0);
        } else {
            try addAtomic(request, plane_id, properties.framebuffer, framebuffers[index % 2]);
            try addAtomic(request, plane_id, properties.crtc, crtc_id);
            try addAtomic(request, plane_id, properties.crtc_x, 64);
            try addAtomic(request, plane_id, properties.crtc_y, 100);
            try addAtomic(request, plane_id, properties.crtc_w, overlay_width);
            try addAtomic(request, plane_id, properties.crtc_h, overlay_height);
            try addAtomic(request, plane_id, properties.src_x, 0);
            try addAtomic(request, plane_id, properties.src_y, 0);
            try addAtomic(request, plane_id, properties.src_w, overlay_width << 16);
            try addAtomic(request, plane_id, properties.src_h, overlay_height << 16);
        }
        var completion: Completion = .{};
        if (drmModeAtomicCommit(fd, request, atomic_nonblock | atomic_page_flip_event, &completion) != 0) return error.ToggleOverlay;
        try waitFlip(fd, &completion);
        overlay_visible = visible;
    }
    std.debug.print("REPRO overlay_enable END\n", .{});

    try disableOverlay(fd, plane_id, properties);
    enabled = false;
    if (enable_only)
        std.debug.print("overlay_enable_exercise=PASS frames={d}\n", .{sample_count})
    else
        std.debug.print("overlay_exercise=PASS moves={d} submit_p50_us={d} submit_p95_us={d} present_p50_us={d} present_p95_us={d}\n", .{
            sample_count,
            submit_us[sample_count / 2],
            submit_us[sample_count * 95 / 100],
            present_us[sample_count / 2],
            present_us[sample_count * 95 / 100],
        });
}

fn atomicOverlayTest(io: std.Io, fd: c_int, resources: *const PlaneResources) !void {
    var crtc_id: u32 = 0;
    var overlay_id: u32 = 0;
    for (resources.planes[0..resources.count]) |plane_id| {
        const plane = drmModeGetPlane(fd, plane_id) orelse return error.GetPlane;
        defer drmModeFreePlane(plane);
        if (plane.crtc != 0 and plane.framebuffer != 0) crtc_id = plane.crtc;
        if (plane.crtc == 0 and std.mem.indexOfScalar(u32, plane.formats[0..plane.format_count], format_argb8888) != null) overlay_id = plane.id;
    }
    if (crtc_id == 0 or overlay_id == 0) return error.NoOverlayCandidate;

    var buffers = [2]TestBuffer{
        try TestBuffer.init(fd, overlay_width, overlay_height, format_argb8888),
        try TestBuffer.init(fd, overlay_width, overlay_height, format_argb8888),
    };
    defer for (&buffers) |*buffer| buffer.deinit(fd);
    buffers[0].fillBars(0xffff00ff, 0xff600060);
    buffers[1].fillBars(0xff00ff40, 0xff006018);

    const properties = try planeProperties(fd, overlay_id);
    const request = drmModeAtomicAlloc() orelse return error.AtomicAlloc;
    defer drmModeAtomicFree(request);
    try addAtomic(request, overlay_id, properties.framebuffer, buffers[0].framebuffer);
    try addAtomic(request, overlay_id, properties.crtc, crtc_id);
    try addAtomic(request, overlay_id, properties.crtc_x, 64);
    try addAtomic(request, overlay_id, properties.crtc_y, 100);
    try addAtomic(request, overlay_id, properties.crtc_w, overlay_width);
    try addAtomic(request, overlay_id, properties.crtc_h, overlay_height);
    try addAtomic(request, overlay_id, properties.src_x, 0);
    try addAtomic(request, overlay_id, properties.src_y, 0);
    try addAtomic(request, overlay_id, properties.src_w, overlay_width << 16);
    try addAtomic(request, overlay_id, properties.src_h, overlay_height << 16);
    if (drmModeAtomicCommit(fd, request, atomic_test_only, null) != 0) {
        std.debug.print("overlay_test=FAIL plane={d} errno={d}\n", .{ overlay_id, __errno_location().* });
        return error.AtomicOverlayCommit;
    }
    std.debug.print("overlay_test=PASS plane={d} format=AR24 size={d}x{d} crtc={d}\n", .{ overlay_id, overlay_width, overlay_height, crtc_id });
    if (getenv("KMS_PLANE_EXERCISE") != null or getenv("KMS_TEARING_SUITE") != null)
        try exerciseOverlay(io, fd, overlay_id, crtc_id, .{ buffers[0].framebuffer, buffers[1].framebuffer }, properties);
}

fn atomicNoop(io: std.Io, fd: c_int, resources: *const PlaneResources) !void {
    if (drmSetMaster(fd) != 0) {
        std.debug.print("atomic_test=SKIP reason=not-master errno={d}\n", .{__errno_location().*});
        return;
    }
    defer _ = drmDropMaster(fd);

    for (resources.planes[0..resources.count]) |plane_id| {
        const plane = drmModeGetPlane(fd, plane_id) orelse return error.GetPlane;
        defer drmModeFreePlane(plane);
        if (plane.crtc == 0 or plane.framebuffer == 0) continue;
        const properties = drmModeObjectGetProperties(fd, plane_id, object_plane) orelse return error.GetProperties;
        defer drmModeFreeObjectProperties(properties);
        for (properties.ids[0..properties.count], properties.values[0..properties.count]) |property_id, value| {
            const property = drmModeGetProperty(fd, property_id) orelse return error.GetProperty;
            defer drmModeFreeProperty(property);
            if (!std.mem.eql(u8, propertyName(property), "CRTC_X")) continue;
            const request = drmModeAtomicAlloc() orelse return error.AtomicAlloc;
            defer drmModeAtomicFree(request);
            if (drmModeAtomicAddProperty(request, plane_id, property_id, value) < 0) return error.AtomicAdd;
            if (drmModeAtomicCommit(fd, request, atomic_test_only, null) != 0) {
                std.debug.print("atomic_test=FAIL plane={d} errno={d}\n", .{ plane_id, __errno_location().* });
                return error.AtomicCommit;
            }
            std.debug.print("atomic_test=PASS plane={d} property=CRTC_X value={d}\n", .{ plane_id, value });
            try atomicOverlayTest(io, fd, resources);
            if (getenv("KMS_TEARING_SUITE") != null) try exercisePrimary(fd, resources);
            return;
        }
    }
    return error.NoCrtcProperty;
}

pub fn main(init: std.process.Init) !void {
    const fd = open("/dev/dri/card0", open_read_write | open_cloexec);
    if (fd < 0) return error.OpenDrm;
    defer _ = close(fd);

    if (drmSetClientCap(fd, client_universal_planes, 1) != 0) return error.UniversalPlanes;
    if (drmSetClientCap(fd, client_atomic, 1) != 0) return error.AtomicCapability;

    const resources = drmModeGetPlaneResources(fd) orelse return error.GetPlaneResources;
    defer drmModeFreePlaneResources(resources);
    std.debug.print("plane_count={d} universal=PASS atomic_cap=PASS\n", .{resources.count});
    for (resources.planes[0..resources.count]) |plane_id| try printPlane(fd, plane_id);
    try atomicNoop(init.io, fd, resources);
}
