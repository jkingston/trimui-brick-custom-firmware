// SPDX-License-Identifier: GPL-2.0-only
// GPU/DMA-BUF experiment. Off-screen by default; GPU_PROBE_PRESENT opts into
// bounded KMS flips. Run presentation under the existing recovery watchdog.
const std = @import("std");
const c = @import("gpu_probe_abi.zig");
const kms = @import("gpu_kms.zig");
const pango = @import("pango");
const width = 1024;
const height = 768;
const frames = 240;
var draw_vertices: c_int = 128 * 6;

fn require(ok: bool, stage: []const u8) !void {
    if (ok) return;
    const errno = c.__errno_location().*;
    std.debug.print("FAIL {s}: errno={d} EGL=0x{x} GL=0x{x}\n", .{ stage, errno, c.eglGetError(), c.glGetError() });
    return error.ProbeFailed;
}

fn sync(fd: c_int, flags: u64) !void {
    var request = c.struct_dma_buf_sync{ .flags = flags };
    try require(c.ioctl(fd, c.DMA_BUF_IOCTL_SYNC, &request) == 0, "DMA_BUF_IOCTL_SYNC");
}

fn benchmark(io: std.Io, damaged: bool) !void {
    var samples: [frames]i64 = undefined;
    if (damaged) c.glEnable(c.GL_SCISSOR_TEST) else c.glDisable(c.GL_SCISSOR_TEST);
    for (0..frames + 20) |frame| {
        const started = std.Io.Timestamp.now(io, .awake);
        c.glClearColor(if (frame % 2 == 0) 1 else 0, 0, 1, 1);
        if (damaged) {
            c.glScissor(28, height - 176 - 108, 968, 108);
            c.glClear(c.GL_COLOR_BUFFER_BIT);
            c.glScissor(28, height - 284 - 108, 968, 108);
            c.glClear(c.GL_COLOR_BUFFER_BIT);
        } else c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glFinish();
        const elapsed = started.durationTo(std.Io.Timestamp.now(io, .awake)).toMicroseconds();
        if (frame >= 20) samples[frame - 20] = elapsed;
    }
    try require(c.glGetError() == c.GL_NO_ERROR, "benchmark clears");
    var sum: i64 = 0;
    for (samples) |sample| sum += sample;
    std.mem.sort(i64, &samples, {}, std.sort.asc(i64));
    std.debug.print("{s}: mean_us={d} p50_us={d} p95_us={d} p99_us={d}\n", .{
        if (damaged) "two_rows" else "full", @divTrunc(sum, frames), samples[frames / 2], samples[frames * 95 / 100], samples[frames * 99 / 100],
    });
}

fn shader(kind: c_uint, source: [*:0]const u8) !c_uint {
    const handle = c.glCreateShader(kind);
    errdefer c.glDeleteShader(handle);
    c.glShaderSource(handle, 1, &.{source}, null);
    c.glCompileShader(handle);
    var status: c_int = 0;
    c.glGetShaderiv(handle, c.GL_COMPILE_STATUS, &status);
    if (status == 0) {
        var log: [2048]u8 = undefined;
        var length: c_int = 0;
        c.glGetShaderInfoLog(handle, log.len, &length, &log);
        std.debug.print("shader: {s}\n", .{log[0..@intCast(length)]});
    }
    try require(status != 0, "compile shader");
    return handle;
}

// Synthetic cached text workload, not actual shaped menu text. One static VBO,
// one resident alpha texture, one draw for 128 nonoverlapping glyph-sized quads.
// Keep resources alive until pixel verification is complete.
const TextBatch = struct {
    program: c_uint,
    texture: c_uint,
    vbo: c_uint,

    fn init() !TextBatch {
        const vs = try shader(c.GL_VERTEX_SHADER, "attribute vec4 vertex; varying vec2 uv; void main(){gl_Position=vec4(vertex.xy,0.,1.);uv=vertex.zw;}");
        defer c.glDeleteShader(vs);
        const fs = try shader(c.GL_FRAGMENT_SHADER, "precision mediump float; varying vec2 uv; uniform sampler2D mask; uniform vec3 color; void main(){gl_FragColor=vec4(color,texture2D(mask,uv).a);}");
        defer c.glDeleteShader(fs);
        var self: TextBatch = .{ .program = c.glCreateProgram(), .texture = 0, .vbo = 0 };
        errdefer self.deinit();
        c.glAttachShader(self.program, vs);
        c.glAttachShader(self.program, fs);
        c.glBindAttribLocation(self.program, 0, "vertex");
        c.glLinkProgram(self.program);
        var linked: c_int = 0;
        c.glGetProgramiv(self.program, c.GL_LINK_STATUS, &linked);
        try require(linked != 0, "link text program");
        c.glUseProgram(self.program);
        c.glUniform3f(c.glGetUniformLocation(self.program, "color"), 0, 1, 0);
        var mask: [8 * 8]u8 = undefined;
        for (&mask, 0..) |*a, i| a.* = switch (i % 8) {
            0...1 => 0,
            2...5 => 128,
            else => 255,
        };
        c.glGenTextures(1, &self.texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_ALPHA, 8, 8, 0, c.GL_ALPHA, c.GL_UNSIGNED_BYTE, &mask);
        var vertices: [128 * 6][4]f32 = undefined;
        const corners = [6][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 } };
        for (0..128) |glyph| {
            const x: f32 = @floatFromInt(48 + (glyph % 64) * 14);
            const y: f32 = @floatFromInt(140 + (glyph / 64) * 108);
            for (corners, 0..) |uv, j| vertices[glyph * 6 + j] = .{
                (x + uv[0] * 12) / 512 - 1, (y + uv[1] * 24) / 384 - 1, uv[0], uv[1],
            };
        }
        c.glGenBuffers(1, &self.vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_STATIC_DRAW);
        c.glEnableVertexAttribArray(0);
        c.glVertexAttribPointer(0, 4, c.GL_FLOAT, 0, 16, null);
        try require(c.glGetError() == c.GL_NO_ERROR, "prepare cached glyph batch");
        return self;
    }

    fn deinit(self: TextBatch) void {
        c.glDeleteBuffers(1, &self.vbo);
        c.glDeleteTextures(1, &self.texture);
        c.glDeleteProgram(self.program);
    }

    fn draw() void {
        c.glDisable(c.GL_SCISSOR_TEST);
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glDrawArrays(c.GL_TRIANGLES, 0, draw_vertices);
        c.glDisable(c.GL_BLEND);
    }

    fn loadShapedText(self: TextBatch) !void {
        var atlas: [1024 * 128]u8 = @splat(0);
        var vertices: [12][4]f32 = undefined;
        const corners = [6][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 } };
        for ([_][]const u8{ "Brightness", "Performance" }, 0..) |label, i| {
            const mask = pango.rasterize(label, .{ .size = 43, .line_height = 52, .ink_centered = true }, 900, 64) orelse return error.TextMask;
            try require(mask.width <= 1024 and mask.height <= 64, "atlas bounds");
            for (0..mask.height) |y| @memcpy(atlas[(i * 64 + y) * 1024 ..][0..mask.width], mask.bytes[y * mask.width ..][0..mask.width]);
            const x: f32 = @floatFromInt(48 + mask.x);
            // Put the top-down Pango mask upright into bottom-up GLES pixels.
            const top: f32 = @floatFromInt(184 + i * 108);
            const w: f32 = @floatFromInt(mask.width);
            const h: f32 = @floatFromInt(mask.height);
            for (corners, 0..) |uv, j| vertices[i * 6 + j] = .{
                (x + uv[0] * w) / 512 - 1, (top - uv[1] * h) / 384 - 1,
                uv[0] * w / 1024,          (@as(f32, @floatFromInt(i * 64)) + uv[1] * h) / 128,
            };
        }
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_ALPHA, 1024, 128, 0, c.GL_ALPHA, c.GL_UNSIGNED_BYTE, &atlas);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_STATIC_DRAW);
        c.glUniform3f(c.glGetUniformLocation(self.program, "color"), 1, 1, 1);
        draw_vertices = 12;
        try require(c.glGetError() == c.GL_NO_ERROR, "upload shaped text atlas");
    }
};

const Completion = struct {
    display: ?*anyopaque,
    create: *const fn (?*anyopaque, c_uint, [*]const c_int) callconv(.c) ?*anyopaque,
    wait: *const fn (?*anyopaque, ?*anyopaque, c_int, u64) callconv(.c) c_int,
    destroy: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_uint,
    fn init(display: ?*anyopaque) !Completion {
        const create = c.eglGetProcAddress("eglCreateSyncKHR") orelse return error.NoFence;
        const wait = c.eglGetProcAddress("eglClientWaitSyncKHR") orelse return error.NoFence;
        const destroy = c.eglGetProcAddress("eglDestroySyncKHR") orelse return error.NoFence;
        return .{ .display = display, .create = @ptrCast(create), .wait = @ptrCast(wait), .destroy = @ptrCast(destroy) };
    }
};
fn textBenchmark(io: std.Io, completion: Completion, merged: bool, fence: bool, idle: bool) !void {
    std.debug.print("workload_vertices={d} merged={} fence={} idle={}\n", .{ draw_vertices, merged, fence, idle });
    var completed: [frames]i64 = undefined;
    var submitted: [frames]i64 = undefined;
    const count: usize = if (idle) 40 else frames;
    const warmup: usize = if (idle) 2 else 20;
    var usage_before: c.Usage = undefined;
    for (0..count + warmup) |frame| {
        if (frame == warmup) try require(c.getrusage(0, &usage_before) == 0, "get resource usage");
        if (idle) _ = c.usleep(250_000);
        const started = std.Io.Timestamp.now(io, .awake);
        c.glEnable(c.GL_SCISSOR_TEST);
        c.glClearColor(if (frame % 2 == 0) 1 else 0, 0, 0, 1);
        c.glScissor(28, 100, 968, if (merged) 216 else 108);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        if (!merged) {
            c.glScissor(28, 208, 968, 108);
            c.glClear(c.GL_COLOR_BUFFER_BIT);
        }
        TextBatch.draw();
        var sync_object = if (fence) completion.create(completion.display, 0x30f9, &.{c.EGL_NONE}) else null;
        defer if (sync_object != null) {
            _ = completion.destroy(completion.display, sync_object);
        };
        if (fence) try require(sync_object != null, "create completion fence");
        c.glFlush();
        const flushed = std.Io.Timestamp.now(io, .awake);
        if (fence) {
            try require(completion.wait(completion.display, sync_object, 0, 2_000_000_000) == 0x30f6, "wait completion fence");
            try require(completion.destroy(completion.display, sync_object) != 0, "destroy completion fence");
            sync_object = null;
        } else c.glFinish();
        const finished = std.Io.Timestamp.now(io, .awake);
        if (frame >= warmup) {
            completed[frame - warmup] = started.durationTo(finished).toMicroseconds();
            submitted[frame - warmup] = started.durationTo(flushed).toMicroseconds();
        }
    }
    try require(c.glGetError() == c.GL_NO_ERROR, "textured draws");
    var usage_after: c.Usage = undefined;
    try require(c.getrusage(0, &usage_after) == 0, "get final resource usage");
    const cpu_us = (usage_after.user.seconds + usage_after.system.seconds - usage_before.user.seconds - usage_before.system.seconds) * 1_000_000 +
        usage_after.user.micros + usage_after.system.micros - usage_before.user.micros - usage_before.system.micros;
    std.debug.print("cpu_us_per_frame={d} voluntary_switches={d} peak_rss_kib={d}\n", .{
        @divTrunc(cpu_us, @as(i64, @intCast(count))), usage_after.counters[12] - usage_before.counters[12], usage_after.counters[0],
    });
    for ([_][]i64{ submitted[0..count], completed[0..count] }, [_][]const u8{ "glyph_submit", "glyph_complete" }) |samples, name| {
        var sum: i64 = 0;
        for (samples) |sample| sum += sample;
        std.mem.sort(i64, samples, {}, std.sort.asc(i64));
        std.debug.print("{s}: mean_us={d} p50_us={d} p95_us={d} p99_us={d}\n", .{
            name, @divTrunc(sum, @as(i64, @intCast(count))), samples[count / 2], samples[count * 95 / 100], samples[count * 99 / 100],
        });
    }
}

const ExtraTarget = struct {
    fd: c_int,
    display: ?*anyopaque,
    buffer: c.struct_drm_mode_create_dumb,
    prime: c_int = -1,
    image: ?*anyopaque = null,
    texture: c_uint = 0,
    framebuffer: c_uint = 0,
    destroy_image: c.PFNEGLDESTROYIMAGEKHRPROC,
    fn init(fd: c_int, display: ?*anyopaque) !ExtraTarget {
        var self = ExtraTarget{ .fd = fd, .display = display, .buffer = std.mem.zeroes(c.struct_drm_mode_create_dumb), .destroy_image = @ptrCast(c.eglGetProcAddress("eglDestroyImageKHR")) };
        errdefer self.deinit();
        self.buffer.width = width;
        self.buffer.height = height;
        self.buffer.bpp = 32;
        try require(c.ioctl(fd, c.DRM_IOCTL_MODE_CREATE_DUMB, &self.buffer) == 0, "second dumb buffer");
        var prime = c.struct_drm_prime_handle{ .handle = self.buffer.handle, .flags = c.DRM_CLOEXEC | c.DRM_RDWR, .fd = -1 };
        try require(c.ioctl(fd, c.DRM_IOCTL_PRIME_HANDLE_TO_FD, &prime) == 0, "second DMA-BUF export");
        self.prime = prime.fd;
        const create: c.PFNEGLCREATEIMAGEKHRPROC = @ptrCast(c.eglGetProcAddress("eglCreateImageKHR"));
        const target: c.PFNGLEGLIMAGETARGETTEXTURE2DOESPROC = @ptrCast(c.eglGetProcAddress("glEGLImageTargetTexture2DOES"));
        const attrs = [_]c_int{ c.EGL_WIDTH, width, c.EGL_HEIGHT, height, c.EGL_LINUX_DRM_FOURCC_EXT, c.DRM_FORMAT_XRGB8888, c.EGL_DMA_BUF_PLANE0_FD_EXT, prime.fd, c.EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0, c.EGL_DMA_BUF_PLANE0_PITCH_EXT, @intCast(self.buffer.pitch), c.EGL_NONE };
        self.image = create.?(display, null, c.EGL_LINUX_DMA_BUF_EXT, null, &attrs);
        try require(self.image != null, "second EGLImage");
        c.glGenTextures(1, &self.texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.texture);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        target.?(c.GL_TEXTURE_2D, self.image);
        c.glGenFramebuffers(1, &self.framebuffer);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.framebuffer);
        c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, self.texture, 0);
        try require(c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) == c.GL_FRAMEBUFFER_COMPLETE, "second render target");
        return self;
    }
    fn deinit(self: ExtraTarget) void {
        c.glDeleteFramebuffers(1, &self.framebuffer);
        c.glDeleteTextures(1, &self.texture);
        if (self.image != null) _ = self.destroy_image.?(self.display, self.image);
        if (self.prime >= 0) _ = c.close(self.prime);
        if (self.buffer.handle != 0) {
            var destroy = c.struct_drm_mode_destroy_dumb{ .handle = self.buffer.handle };
            _ = c.ioctl(self.fd, c.DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
        }
    }
};

fn presentBenchmark(io: std.Io, fd: c_int, display: ?*anyopaque, first: c.struct_drm_mode_create_dumb, framebuffer: c_uint, text: TextBatch) !void {
    const second = try ExtraTarget.init(fd, display);
    defer second.deinit();
    var presenter = try kms.Presenter.init(fd, .{ first.handle, second.buffer.handle }, .{ first.pitch, second.buffer.pitch });
    defer presenter.deinit();
    const targets = [_]c_uint{ framebuffer, second.framebuffer };
    for (targets) |fb| {
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, fb);
        c.glDisable(c.GL_SCISSOR_TEST);
        c.glClearColor(0.04, 0.04, 0.04, 1);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
    }
    c.glFinish();
    c.glBindTexture(c.GL_TEXTURE_2D, text.texture);
    try presenter.start();
    const count: usize = if (c.getenv("GPU_PROBE_FRAMES")) |value| try std.fmt.parseInt(usize, std.mem.span(value), 10) else 120;
    if (count < 120 or count > 1200) return error.UnsafeFrameCount;
    var render_us: [1200]i64 = undefined;
    var total_us: [1200]i64 = undefined;
    var last_vblank: u64 = 0;
    var long_gaps: usize = 0;
    const phase_us: u32 = if (c.getenv("GPU_PROBE_PHASE_US")) |value| try std.fmt.parseInt(u32, std.mem.span(value), 10) else 0;
    if (phase_us > 15000) return error.UnsafePhase;
    std.debug.print("kms_phase_delay_us={d}; test-only fixed phase, not an input-latency measurement\n", .{phase_us});
    for (0..count) |frame| {
        const back = (frame + 1) % 2;
        if (frame != 0 and phase_us != 0) _ = c.usleep(phase_us);
        const started = std.Io.Timestamp.now(io, .awake);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, targets[back]);
        c.glEnable(c.GL_SCISSOR_TEST);
        c.glClearColor(if (frame % 4 < 2) 0.25 else 0.5, 0.1, 0.1, 1);
        c.glScissor(28, 100, 968, 216);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        TextBatch.draw();
        c.glFinish(); // Proven completion first; do not assume cross-driver implicit fences.
        render_us[frame] = started.durationTo(std.Io.Timestamp.now(io, .awake)).toMicroseconds();
        const vblank = try presenter.present(back);
        total_us[frame] = started.durationTo(std.Io.Timestamp.now(io, .awake)).toMicroseconds();
        if (last_vblank != 0 and vblank - last_vblank > 20000) long_gaps += 1;
        last_vblank = vblank;
    }
    for ([_][]i64{ render_us[0..count], total_us[0..count] }, [_][]const u8{ "kms_render", "kms_render_to_flip_event" }) |samples, label| {
        var sum: i64 = 0;
        for (samples) |n| sum += n;
        std.mem.sort(i64, samples, {}, std.sort.asc(i64));
        std.debug.print("{s}: mean_us={d} p50_us={d} p95_us={d} p99_us={d}\n", .{ label, @divTrunc(sum, @as(i64, @intCast(samples.len))), samples[count / 2], samples[count * 95 / 100], samples[count * 99 / 100] });
    }
    try require(c.glGetError() == c.GL_NO_ERROR, "KMS textured frames");
    std.debug.print("kms_frames={d} vblank_gaps_over_20ms={d}; event timing is not photon timing\n", .{ count, long_gaps });
    try presenter.restore();
}

fn verifyShapedText(fd: c_int, pixels: [*]volatile u32, pitch: u32) !void {
    c.glDisable(c.GL_SCISSOR_TEST);
    c.glClearColor(0, 0, 0, 1);
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    TextBatch.draw();
    c.glFinish();
    var expected: [width * height]u8 = @splat(0);
    for ([_][]const u8{ "Brightness", "Performance" }, 0..) |label, i| {
        const mask = pango.rasterize(label, .{ .size = 43, .line_height = 52, .ink_centered = true }, 900, 64) orelse return error.TextMask;
        for (0..mask.height) |y| @memcpy(expected[(183 + i * 108 - y) * width + 48 + mask.x ..][0..mask.width], mask.bytes[y * mask.width ..][0..mask.width]);
    }
    try sync(fd, c.DMA_BUF_SYNC_START | c.DMA_BUF_SYNC_READ);
    defer sync(fd, c.DMA_BUF_SYNC_END | c.DMA_BUF_SYNC_READ) catch {};
    for (expected, 0..) |coverage, i| {
        const actual = pixels[(i / width) * (pitch / 4) + i % width];
        inline for (.{ 0, 8, 16 }) |shift| {
            const delta = @as(i32, @intCast((actual >> shift) & 255)) - @as(i32, coverage);
            if (@abs(delta) > 1) {
                std.debug.print("shaped pixel mismatch x={d} y={d} rgba=0x{x} expected={d}\n", .{ i % width, i / width, actual, coverage });
                return error.ShapedPixelMismatch;
            }
        }
    }
    std.debug.print("PASS: Pango-shaped GPU text matches CPU coverage over entire buffer\n", .{});
}

pub fn main(init: std.process.Init) !void {
    const fd = c.open("/dev/dri/card0", c.O_RDWR | c.O_CLOEXEC);
    try require(fd >= 0, "open display DRM");
    defer _ = c.close(fd);
    var buffer = std.mem.zeroes(c.struct_drm_mode_create_dumb);
    buffer.width = width;
    buffer.height = height;
    buffer.bpp = 32;
    try require(c.ioctl(fd, c.DRM_IOCTL_MODE_CREATE_DUMB, &buffer) == 0, "allocate dumb buffer");
    defer {
        var destroy = c.struct_drm_mode_destroy_dumb{ .handle = buffer.handle };
        _ = c.ioctl(fd, c.DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
    }
    var map = std.mem.zeroes(c.struct_drm_mode_map_dumb);
    map.handle = buffer.handle;
    try require(c.ioctl(fd, c.DRM_IOCTL_MODE_MAP_DUMB, &map) == 0, "map dumb buffer");
    const memory = c.mmap(null, buffer.size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, @intCast(map.offset));
    try require(memory != c.MAP_FAILED and memory != null, "mmap");
    defer _ = c.munmap(memory, buffer.size);
    const pixels: [*]volatile u32 = @ptrCast(@alignCast(memory.?));
    var prime = c.struct_drm_prime_handle{ .handle = buffer.handle, .flags = c.DRM_CLOEXEC | c.DRM_RDWR, .fd = -1 };
    try require(c.ioctl(fd, c.DRM_IOCTL_PRIME_HANDLE_TO_FD, &prime) == 0, "export DMA-BUF");
    defer _ = c.close(prime.fd);
    try sync(prime.fd, c.DMA_BUF_SYNC_START | c.DMA_BUF_SYNC_WRITE);
    @memset(@as([*]u8, @ptrCast(memory.?))[0..buffer.size], 0x5a);
    try sync(prime.fd, c.DMA_BUF_SYNC_END | c.DMA_BUF_SYNC_WRITE);

    std.debug.print("stage=egl-initialize pitch={d} bytes={d}\n", .{ buffer.pitch, buffer.size });
    const display = c.eglGetDisplay(c.EGL_DEFAULT_DISPLAY);
    var major: c_int = 0;
    var minor: c_int = 0;
    try require(display != null and c.eglInitialize(display, &major, &minor) != 0, "eglInitialize");
    defer _ = c.eglTerminate(display);
    const extensions = std.mem.span(c.eglQueryString(display, c.EGL_EXTENSIONS));
    std.debug.print("EGL={d}.{d} extensions={s}\n", .{ major, minor, extensions });
    try require(std.mem.indexOf(u8, extensions, "EGL_EXT_image_dma_buf_import") != null, "DMA-BUF extension");
    try require(c.eglBindAPI(c.EGL_OPENGL_ES_API) != 0, "bind GLES");
    const config_attrs = [_]c_int{ c.EGL_SURFACE_TYPE, c.EGL_PBUFFER_BIT, c.EGL_RENDERABLE_TYPE, c.EGL_OPENGL_ES2_BIT, c.EGL_RED_SIZE, 8, c.EGL_GREEN_SIZE, 8, c.EGL_BLUE_SIZE, 8, c.EGL_NONE };
    var config: c.EGLConfig = null;
    var count: c_int = 0;
    try require(c.eglChooseConfig(display, &config_attrs, &config, 1, &count) != 0 and count == 1, "choose config");
    const surface_attrs = [_]c_int{ c.EGL_WIDTH, 1, c.EGL_HEIGHT, 1, c.EGL_NONE };
    const surface = c.eglCreatePbufferSurface(display, config, &surface_attrs);
    try require(surface != null, "create pbuffer");
    defer _ = c.eglDestroySurface(display, surface);
    const context_attrs = [_]c_int{ c.EGL_CONTEXT_CLIENT_VERSION, 2, c.EGL_NONE };
    const context = c.eglCreateContext(display, config, null, &context_attrs);
    try require(context != null, "create context");
    defer _ = c.eglDestroyContext(display, context);
    try require(c.eglMakeCurrent(display, surface, surface, context) != 0, "make current");
    defer _ = c.eglMakeCurrent(display, null, null, null);
    const renderer = std.mem.span(c.glGetString(c.GL_RENDERER));
    std.debug.print("renderer={s} version={s}\n", .{ renderer, std.mem.span(c.glGetString(c.GL_VERSION)) });
    try require(std.mem.indexOf(u8, renderer, "PowerVR") != null, "require hardware PowerVR");
    const create_image: c.PFNEGLCREATEIMAGEKHRPROC = @ptrCast(c.eglGetProcAddress("eglCreateImageKHR"));
    const destroy_image: c.PFNEGLDESTROYIMAGEKHRPROC = @ptrCast(c.eglGetProcAddress("eglDestroyImageKHR"));
    const target: c.PFNGLEGLIMAGETARGETTEXTURE2DOESPROC = @ptrCast(c.eglGetProcAddress("glEGLImageTargetTexture2DOES"));
    try require(create_image != null and destroy_image != null and target != null, "image entry points");
    const image_attrs = [_]c_int{ c.EGL_WIDTH, width, c.EGL_HEIGHT, height, c.EGL_LINUX_DRM_FOURCC_EXT, c.DRM_FORMAT_XRGB8888, c.EGL_DMA_BUF_PLANE0_FD_EXT, prime.fd, c.EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0, c.EGL_DMA_BUF_PLANE0_PITCH_EXT, @intCast(buffer.pitch), c.EGL_NONE };
    const image = create_image.?(display, null, c.EGL_LINUX_DMA_BUF_EXT, null, &image_attrs);
    try require(image != null, "import DMA-BUF EGLImage");
    defer _ = destroy_image.?(display, image);
    var texture: c_uint = 0;
    c.glGenTextures(1, &texture);
    defer c.glDeleteTextures(1, &texture);
    c.glBindTexture(c.GL_TEXTURE_2D, texture);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    target.?(c.GL_TEXTURE_2D, image);
    try require(c.glGetError() == c.GL_NO_ERROR, "bind EGLImage texture");
    var framebuffer: c_uint = 0;
    c.glGenFramebuffers(1, &framebuffer);
    defer c.glDeleteFramebuffers(1, &framebuffer);
    c.glBindFramebuffer(c.GL_FRAMEBUFFER, framebuffer);
    c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, texture, 0);
    const status = c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER);
    std.debug.print("framebuffer_status=0x{x}\n", .{status});
    try require(status == c.GL_FRAMEBUFFER_COMPLETE, "renderable DMA-BUF");
    c.glViewport(0, 0, width, height);
    c.glDisable(c.GL_DITHER);
    try benchmark(init.io, false);
    try benchmark(init.io, true);
    const batch = try TextBatch.init();
    defer batch.deinit();
    const completion = try Completion.init(display);
    try textBenchmark(init.io, completion, false, false, false);
    try textBenchmark(init.io, completion, true, false, false);
    try textBenchmark(init.io, completion, true, true, false);
    // Verify the same retained texture after power-collapse/wake cycles too.
    if (c.getenv("GPU_PROBE_IDLE") != null) try textBenchmark(init.io, completion, true, false, true);

    // Verify every pixel and preserved pixels, not merely that one byte changed.
    c.glDisable(c.GL_SCISSOR_TEST);
    c.glClearColor(1, 0, 0, 1);
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    c.glEnable(c.GL_SCISSOR_TEST);
    c.glScissor(28, 100, 968, 108);
    c.glClearColor(0, 1, 0, 1);
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    TextBatch.draw();
    c.glFinish();
    try require(c.glGetError() == c.GL_NO_ERROR, "verification render");
    try sync(prime.fd, c.DMA_BUF_SYNC_START | c.DMA_BUF_SYNC_READ);
    var reading = true;
    defer if (reading) {
        sync(prime.fd, c.DMA_BUF_SYNC_END | c.DMA_BUF_SYNC_READ) catch {};
    };
    for (0..height) |y| for (0..width) |x| {
        var expected: u32 = if (y >= 100 and y < 208 and x >= 28 and x < 996) 0x00ff00 else 0xff0000;
        if (y >= 248 and y < 272 and x >= 48 and x < 48 + 64 * 14 and (x - 48) % 14 < 12) {
            const texel = ((x - 48) % 14 * 2 + 1) / 3;
            expected = switch (texel) {
                0...1 => 0xff0000,
                2...5 => 0x7f8000,
                else => 0x00ff00,
            };
        }
        const actual = pixels[y * (buffer.pitch / 4) + x] & 0xffffff;
        var matches = true;
        // GLES normalized blending is allowed one quantization unit of error.
        inline for (.{ 0, 8, 16 }) |shift| {
            const delta = @as(i32, @intCast((actual >> shift) & 255)) - @as(i32, @intCast((expected >> shift) & 255));
            matches = matches and @abs(delta) <= 1;
        }
        if (!matches) {
            std.debug.print("pixel mismatch x={d} y={d} actual=0x{x} expected=0x{x}\n", .{ x, y, actual, expected });
            return error.PixelMismatch;
        }
    };
    std.debug.print("PASS: all shared-buffer pixels match; no CPU framebuffer copy\n", .{});
    // Release CPU access before any subsequent GPU work.
    try sync(prime.fd, c.DMA_BUF_SYNC_END | c.DMA_BUF_SYNC_READ);
    reading = false;
    if (c.getenv("GPU_PROBE_TEXT") != null) {
        try batch.loadShapedText();
        try textBenchmark(init.io, completion, true, false, false);
        try verifyShapedText(prime.fd, pixels, buffer.pitch);
    }
    if (c.getenv("GPU_PROBE_PRESENT") != null) try presentBenchmark(init.io, fd, display, buffer, framebuffer, batch);
}
