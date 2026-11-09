// SPDX-License-Identifier: GPL-2.0-only
// One UI-thread owner, three cached layer pairs, bounded resident textures. No
// CPU framebuffer uploads: Pango coverage and decoded artwork are source textures.
const std = @import("std");
const c = @import("gpu_abi.zig");
const gl = @import("gpu_api.zig");
const kms = @import("gpu_kms.zig");
const scene_cache = @import("gpu_scene_cache.zig");
const texture_cache = @import("gpu_texture_cache.zig");
const ui = @import("ui_scene.zig");
const damage = @import("damage.zig");
const composition = @import("composition.zig");
const render = @import("render.zig");
const assets = @import("asset_manifest.zig");
const texture_batch = @import("texture_batch.zig");
const width = 1024;
const height = 768;

const Target = struct {
    buffer: c.struct_drm_mode_create_dumb = std.mem.zeroes(c.struct_drm_mode_create_dumb),
    prime: c_int = -1,
    image: ?*anyopaque = null,
    texture: c_uint = 0,
    framebuffer: c_uint = 0,
};
const Vertex = extern struct { x: f32, y: f32, u: f32, v: f32, rgba: [4]u8, slot: f32 };

fn pixelCoordinate(normalized: f32, scale: f32) u16 {
    return @intFromFloat(@round((normalized + 1) * scale));
}

test "quad coordinates recover every integer screen boundary" {
    for ([_]usize{ width, height }) |extent| {
        const scale: f32 = @as(f32, @floatFromInt(extent)) / 2;
        for (0..extent + 1) |pixel| {
            const normalized = @as(f32, @floatFromInt(pixel)) / scale - 1;
            try std.testing.expectEqual(@as(u16, @intCast(pixel)), pixelCoordinate(normalized, scale));
        }
    }
}

pub const Profile = struct {
    prepare_us: i64 = 0,
    scene_us: i64 = 0,
    submit_us: i64 = 0,
    target_us: i64 = 0,
    draw_state_us: i64 = 0,
    draw_us: i64 = 0,
    clear_us: i64 = 0,
    complete_us: i64 = 0,
    fence_create_us: i64 = 0,
    fence_wait_us: i64 = 0,
    fence_destroy_us: i64 = 0,
    present_us: i64 = 0,
    draw_calls: usize = 0,
    clear_calls: usize = 0,
    upload_bytes: usize = 0,
    damage_pixels: usize = 0,
    texture_evictions: usize = 0,
};

const Completion = struct {
    create: *const fn (?*anyopaque, c_uint, [*]const c_int) callconv(.c) ?*anyopaque,
    wait: *const fn (?*anyopaque, ?*anyopaque, c_int, u64) callconv(.c) c_int,
    destroy: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_uint,

    fn init() !Completion {
        return .{
            .create = @ptrCast(gl.api.eglGetProcAddress("eglCreateSyncKHR") orelse return error.NoGpuFence),
            .wait = @ptrCast(gl.api.eglGetProcAddress("eglClientWaitSyncKHR") orelse return error.NoGpuFence),
            .destroy = @ptrCast(gl.api.eglGetProcAddress("eglDestroySyncKHR") orelse return error.NoGpuFence),
        };
    }

    fn finish(self: Completion, io: std.Io, display: ?*anyopaque, profile: ?*Profile) !void {
        const started = if (profile != null) std.Io.Timestamp.now(io, .awake).toMicroseconds() else 0;
        const fence = self.create(display, c.EGL_SYNC_FENCE_KHR, &.{c.EGL_NONE}) orelse return error.GpuFenceCreate;
        const created = if (profile != null) std.Io.Timestamp.now(io, .awake).toMicroseconds() else 0;
        defer {
            const waited = if (profile != null) std.Io.Timestamp.now(io, .awake).toMicroseconds() else 0;
            _ = self.destroy(display, fence);
            if (profile) |timings| {
                timings.fence_create_us = created - started;
                timings.fence_wait_us = waited - created;
                timings.fence_destroy_us = std.Io.Timestamp.now(io, .awake).toMicroseconds() - waited;
            }
        }
        // The GPU and display drivers do not share implicit completion fences.
        if (self.wait(display, fence, c.EGL_SYNC_FLUSH_COMMANDS_BIT_KHR, 2_000_000_000) != c.EGL_CONDITION_SATISFIED_KHR) return error.GpuCompletion;
    }
};

pub const Display = struct {
    fd: c_int = -1,
    display: ?*anyopaque = null,
    surface: ?*anyopaque = null,
    context: ?*anyopaque = null,
    targets: [kms.buffer_count]Target = @splat(.{}),
    overlays: [kms.buffer_count]Target = @splat(.{}),
    presenter: ?kms.Presenter = null,
    completion: ?Completion = null,
    image_create: c.PFNEGLCREATEIMAGEKHRPROC = null,
    image_destroy: c.PFNEGLDESTROYIMAGEKHRPROC = null,
    image_target: c.PFNGLEGLIMAGETARGETTEXTURE2DOESPROC = null,
    program: c_uint = 0,
    kind_uniform: c_int = -1,
    bounds_uniform: c_int = -1,
    crop_uniform: c_int = -1,
    size_uniform: c_int = -1,
    art_uniform: c_int = -1,
    vertices: [4092]Vertex = @splat(std.mem.zeroes(Vertex)),
    vertex_count: usize = 0,
    gpu_pending: bool = false,
    clips: []const ui.Rect = &.{},
    batch_kind: u8 = 0,
    batch: texture_batch.Batch = .{},
    texture_cache: texture_cache.Cache = .{},
    failure: ?anyerror = null,
    cache: scene_cache.Cache = .{},
    front: usize = 0,
    queued_target: ?usize = null,
    selection: ?ui.Rect = null,
    queued_selection: ?ui.Rect = null,
    started: bool = false,
    frames: usize = 0,
    render_total_us: i64 = 0,
    profiling: bool = false,
    profile_io: ?std.Io = null,
    last: Profile = .{},
    last_flip_us: u64 = 0,
    last_work_us: i64 = 0,
    submitted_us: i64 = 0,

    pub fn open() !*Display {
        try gl.init();
        const self = try std.heap.page_allocator.create(Display);
        self.* = .{};
        errdefer self.close();
        self.fd = c.open("/dev/dri/card0", c.O_RDWR | c.O_CLOEXEC);
        if (self.fd < 0) return error.DisplayOpen;
        self.display = gl.api.eglGetDisplay(null);
        var major: c_int = 0;
        var minor: c_int = 0;
        if (self.display == null or gl.api.eglInitialize(self.display, &major, &minor) == 0) return error.EglInitialize;
        if (std.mem.indexOf(u8, std.mem.span(gl.api.eglQueryString(self.display, c.EGL_EXTENSIONS)), "EGL_EXT_image_dma_buf_import") == null) return error.NoDmaBufImport;
        if (gl.api.eglBindAPI(c.EGL_OPENGL_ES_API) == 0) return error.EglApi;
        var config: c.EGLConfig = null;
        var count: c_int = 0;
        if (gl.api.eglChooseConfig(self.display, &.{ c.EGL_SURFACE_TYPE, c.EGL_PBUFFER_BIT, c.EGL_RENDERABLE_TYPE, c.EGL_OPENGL_ES2_BIT, c.EGL_RED_SIZE, 8, c.EGL_GREEN_SIZE, 8, c.EGL_BLUE_SIZE, 8, c.EGL_NONE }, &config, 1, &count) == 0 or count != 1) return error.EglConfig;
        self.surface = gl.api.eglCreatePbufferSurface(self.display, config, &.{ c.EGL_WIDTH, 1, c.EGL_HEIGHT, 1, c.EGL_NONE });
        if (self.surface == null) return error.EglSurface;
        self.context = gl.api.eglCreateContext(self.display, config, null, &.{ c.EGL_CONTEXT_CLIENT_VERSION, 2, c.EGL_NONE });
        if (self.context == null or gl.api.eglMakeCurrent(self.display, self.surface, self.surface, self.context) == 0) {
            std.log.info("EGL context/make-current error=0x{x}", .{gl.api.eglGetError()});
            return error.EglContext;
        }
        const renderer = std.mem.span(gl.api.glGetString(c.GL_RENDERER));
        if (std.mem.indexOf(u8, renderer, "PowerVR") == null) return error.NotHardwareRenderer;
        var texture_units: c_int = 0;
        gl.api.glGetIntegerv(c.GL_MAX_TEXTURE_IMAGE_UNITS, &texture_units);
        std.log.info("brick renderer: {s}, direct DMA-BUF/KMS, texture units={d}", .{ renderer, texture_units });
        if (texture_units < texture_batch.capacity) return error.TextureUnitLimit;
        self.completion = try Completion.init();
        self.image_create = @ptrCast(gl.api.eglGetProcAddress("eglCreateImageKHR"));
        self.image_destroy = @ptrCast(gl.api.eglGetProcAddress("eglDestroyImageKHR"));
        self.image_target = @ptrCast(gl.api.eglGetProcAddress("glEGLImageTargetTexture2DOES"));
        if (self.image_create == null or self.image_destroy == null or self.image_target == null) return error.NoEglImage;
        for (&self.targets) |*target| try self.createTarget(target, c.DRM_FORMAT_XRGB8888);
        for (&self.overlays) |*target| try self.createTarget(target, c.DRM_FORMAT_ARGB8888);
        self.presenter = try kms.Presenter.init(
            self.fd,
            .{ self.targets[0].buffer.handle, self.targets[1].buffer.handle, self.targets[2].buffer.handle },
            .{ self.targets[0].buffer.pitch, self.targets[1].buffer.pitch, self.targets[2].buffer.pitch },
            .{ self.overlays[0].buffer.handle, self.overlays[1].buffer.handle, self.overlays[2].buffer.handle },
            .{ self.overlays[0].buffer.pitch, self.overlays[1].buffer.pitch, self.overlays[2].buffer.pitch },
        );
        try self.createProgram();
        gl.api.glViewport(0, 0, width, height);
        gl.api.glDisable(c.GL_DITHER);
        gl.api.glDisable(c.GL_SCISSOR_TEST);
        gl.api.glEnable(c.GL_BLEND);
        gl.api.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        gl.api.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        try self.check();
        return self;
    }

    fn createTarget(self: *Display, target: *Target, format: c_int) !void {
        target.buffer.width = width;
        target.buffer.height = height;
        target.buffer.bpp = 32;
        if (c.ioctl(self.fd, c.DRM_IOCTL_MODE_CREATE_DUMB, &target.buffer) != 0) return error.DumbBuffer;
        var prime = c.struct_drm_prime_handle{ .handle = target.buffer.handle, .flags = c.DRM_CLOEXEC | c.DRM_RDWR, .fd = -1 };
        if (c.ioctl(self.fd, c.DRM_IOCTL_PRIME_HANDLE_TO_FD, &prime) != 0) return error.DmaBufExport;
        target.prime = prime.fd;
        target.image = self.image_create.?(self.display, null, c.EGL_LINUX_DMA_BUF_EXT, null, &.{ c.EGL_WIDTH, width, c.EGL_HEIGHT, height, c.EGL_LINUX_DRM_FOURCC_EXT, format, c.EGL_DMA_BUF_PLANE0_FD_EXT, prime.fd, c.EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0, c.EGL_DMA_BUF_PLANE0_PITCH_EXT, @intCast(target.buffer.pitch), c.EGL_NONE });
        if (target.image == null) return error.DmaBufImport;
        gl.api.glGenTextures(1, &target.texture);
        gl.api.glBindTexture(c.GL_TEXTURE_2D, target.texture);
        sampling();
        self.image_target.?(c.GL_TEXTURE_2D, target.image);
        gl.api.glGenFramebuffers(1, &target.framebuffer);
        gl.api.glBindFramebuffer(c.GL_FRAMEBUFFER, target.framebuffer);
        gl.api.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, target.texture, 0);
        if (gl.api.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) return error.RenderTarget;
    }

    fn compile(kind: c_uint, source: [*:0]const u8) !c_uint {
        const shader = gl.api.glCreateShader(kind);
        errdefer gl.api.glDeleteShader(shader);
        gl.api.glShaderSource(shader, 1, &.{source}, null);
        gl.api.glCompileShader(shader);
        var status: c_int = 0;
        gl.api.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &status);
        if (status == 0) {
            // SAFETY: The GL API writes the reported prefix before it is read.
            var log: [2048]u8 = undefined;
            var length: c_int = 0;
            gl.api.glGetShaderInfoLog(shader, log.len, &length, &log);
            std.log.info("GPU shader: {s}", .{log[0..@intCast(@max(0, length))]});
            return error.ShaderCompile;
        }
        return shader;
    }

    fn createProgram(self: *Display) !void {
        const vs = try compile(c.GL_VERTEX_SHADER,
            \\attribute vec4 position;
            \\attribute vec4 color;
            \\attribute float textureSlot;
            \\varying vec2 uv;
            \\varying vec4 tint;
            \\varying float slot;
            \\void main() {
            \\    gl_Position = vec4(position.xy, 0., 1.);
            \\    uv = position.zw;
            \\    tint = color;
            \\    slot = textureSlot;
            \\}
        );
        defer gl.api.glDeleteShader(vs);
        const fs = try compile(c.GL_FRAGMENT_SHADER,
            \\precision highp float;
            \\varying vec2 uv;
            \\varying vec4 tint;
            \\varying float slot;
            \\uniform sampler2D image0;
            \\uniform sampler2D image1;
            \\uniform sampler2D image2;
            \\uniform sampler2D image3;
            \\uniform sampler2D image4;
            \\uniform sampler2D image5;
            \\uniform sampler2D image6;
            \\uniform sampler2D image7;
            \\uniform float kind;
            \\uniform vec4 bounds;
            \\uniform vec4 crop;
            \\uniform vec2 size;
            \\uniform vec2 art;
            \\float floorDivide(float n, float d) {
            \\    // Correct reciprocal rounding at exact source-pixel boundaries.
            \\    float q = floor(n / d);
            \\    return q + step((q + 1.) * d, n);
            \\}
            \\void main() {
            \\    vec4 outc = tint;
            \\    if (kind > 1.5) {
            \\        vec2 p = floor(gl_FragCoord.xy) - bounds.xy;
            \\        float farx = art.y < 0. ? p.x : bounds.z - 1. - p.x;
            \\        float inset = floorDivide(farx * abs(art.y) * bounds.w, max(1., bounds.z * 8000.));
            \\        if (p.y < inset || p.y >= bounds.w - inset) discard;
            \\        vec2 q = vec2(floorDivide(p.x * crop.z, bounds.z),
            \\                      floorDivide((p.y - inset) * crop.w, bounds.w - 2. * inset)) + crop.xy;
            \\        outc = texture2D(image0, (q + 0.5) / size).bgra;
            \\        outc.rgb = floor(mix(outc.rgb * 255., tint.rgb * 255., art.x) + 0.5) / 255.;
            \\    } else if (slot >= 0.) {
            \\        vec4 sampled;
            \\        if (slot < 0.5) sampled = texture2D(image0, uv);
            \\        else if (slot < 1.5) sampled = texture2D(image1, uv);
            \\        else if (slot < 2.5) sampled = texture2D(image2, uv);
            \\        else if (slot < 3.5) sampled = texture2D(image3, uv);
            \\        else if (slot < 4.5) sampled = texture2D(image4, uv);
            \\        else if (slot < 5.5) sampled = texture2D(image5, uv);
            \\        else if (slot < 6.5) sampled = texture2D(image6, uv);
            \\        else sampled = texture2D(image7, uv);
            \\        outc.a *= sampled.a;
            \\    }
            \\    gl_FragColor = outc;
            \\}
        );
        defer gl.api.glDeleteShader(fs);
        self.program = try linkProgram(vs, fs);
        gl.api.glUseProgram(self.program);
        for ([_][*:0]const u8{ "image0", "image1", "image2", "image3", "image4", "image5", "image6", "image7" }, 0..) |name, index|
            gl.api.glUniform1i(gl.api.glGetUniformLocation(self.program, name), @intCast(index));
        self.kind_uniform = gl.api.glGetUniformLocation(self.program, "kind");
        self.bounds_uniform = gl.api.glGetUniformLocation(self.program, "bounds");
        self.crop_uniform = gl.api.glGetUniformLocation(self.program, "crop");
        self.size_uniform = gl.api.glGetUniformLocation(self.program, "size");
        self.art_uniform = gl.api.glGetUniformLocation(self.program, "art");
        gl.api.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
        gl.api.glEnableVertexAttribArray(0);
        gl.api.glEnableVertexAttribArray(1);
        gl.api.glEnableVertexAttribArray(2);
        gl.api.glVertexAttribPointer(0, 4, c.GL_FLOAT, 0, @sizeOf(Vertex), &self.vertices[0].x);
        gl.api.glVertexAttribPointer(1, 4, c.GL_UNSIGNED_BYTE, 1, @sizeOf(Vertex), &self.vertices[0].rgba);
        gl.api.glVertexAttribPointer(2, 1, c.GL_FLOAT, 0, @sizeOf(Vertex), &self.vertices[0].slot);
    }

    fn linkProgram(vs: c_uint, fs: c_uint) !c_uint {
        const program = gl.api.glCreateProgram();
        errdefer gl.api.glDeleteProgram(program);
        gl.api.glAttachShader(program, vs);
        gl.api.glAttachShader(program, fs);
        gl.api.glBindAttribLocation(program, 0, "position");
        gl.api.glBindAttribLocation(program, 1, "color");
        gl.api.glBindAttribLocation(program, 2, "textureSlot");
        gl.api.glLinkProgram(program);
        var status: c_int = 0;
        gl.api.glGetProgramiv(program, c.GL_LINK_STATUS, &status);
        if (status == 0) return error.ShaderLink;
        return program;
    }

    pub fn show(self: *Display, io: std.Io, tree: *const ui.Tree) !void {
        try self.wait(io);
        try self.submit(io, tree);
        try self.wait(io);
    }

    pub fn inFlight(self: *const Display) bool {
        return if (self.presenter) |presenter| presenter.pending else false;
    }

    pub fn planeOnly(self: *Display, tree: *const ui.Tree) bool {
        if (!self.started or self.inFlight()) return false;
        const plan = composition.split(tree);
        const previous = if (self.cache.base[self.front]) |*old| old else return false;
        const atlas_previous = if (self.cache.atlas[self.front]) |*old| old else return false;
        const next = damage.Scene.captureAfter(&plan.base, previous);
        const atlas_next = damage.Scene.captureAfter(&plan.atlas, atlas_previous);
        const selection = if (plan.selection) |selected| selected.bounds else null;
        return self.cache.find(&next, &atlas_next) != null and
            (!self.cache.matches(self.front, &next, &atlas_next) or !std.meta.eql(selection, self.selection));
    }

    pub fn wait(self: *Display, io: std.Io) !void {
        if (self.inFlight()) try self.presented(io, try self.presenter.?.wait());
    }

    pub fn dispatch(self: *Display, io: std.Io) !bool {
        if (try self.presenter.?.dispatch()) |timestamp| {
            try self.presented(io, timestamp);
            return true;
        }
        return false;
    }

    fn presented(self: *Display, io: std.Io, timestamp: u64) !void {
        self.front = self.queued_target orelse return error.NoPendingFrame;
        self.queued_target = null;
        self.cache.touch(self.front);
        self.selection = self.queued_selection;
        self.last_flip_us = timestamp;
        if (self.profiling) self.last.present_us = std.Io.Timestamp.now(io, .awake).toMicroseconds() - self.submitted_us;
        self.frames += 1;
    }

    pub fn submit(self: *Display, io: std.Io, tree: *const ui.Tree) !void {
        if (self.inFlight()) return error.FramePending;
        if (self.profiling) self.profile_io = io;
        self.last = .{};
        self.last_flip_us = 0;
        self.last_work_us = 0;
        const scene_started = std.Io.Timestamp.now(io, .awake);
        if (tree.preserve_background) return error.GpuPreservedBackgroundUnsupported;
        const plan = composition.split(tree);
        const previous = if (self.cache.base[self.front]) |*old| old else null;
        const next = damage.Scene.captureAfter(&plan.base, previous);
        const atlas_previous = if (self.cache.atlas[self.front]) |*old| old else null;
        const atlas_next = damage.Scene.captureAfter(&plan.atlas, atlas_previous);
        const selection = if (plan.selection) |selected| selected.bounds else null;
        if (self.profiling) self.last.scene_us = scene_started.durationTo(std.Io.Timestamp.now(io, .awake)).toMicroseconds();
        const current_matches = self.started and self.cache.matches(self.front, &next, &atlas_next);
        if (current_matches and std.meta.eql(selection, self.selection)) return;
        const target = if (!self.started) 0 else self.cache.find(&next, &atlas_next) orelse self.cache.replacement(self.front);
        const render_base = !self.cache.matches(target, &next, &atlas_next) and
            (self.cache.base[target] == null or damage.Scene.changes(&self.cache.base[target].?, &next).slice().len != 0);
        const render_atlas = !self.cache.matches(target, &next, &atlas_next) and
            (self.cache.atlas[target] == null or damage.Scene.changes(&self.cache.atlas[target].?, &atlas_next).slice().len != 0);
        const pending = if (render_base) damage.Scene.changes(if (self.cache.base[target]) |*old| old else null, &next) else damage.RectSet{};
        if (self.profiling) {
            for (pending.slice()) |bounds| self.last.damage_pixels += @as(usize, bounds.width) * bounds.height;
        }
        const started = std.Io.Timestamp.now(io, .awake);
        if (self.profiling) self.last.scene_us = scene_started.durationTo(started).toMicroseconds();
        var submitted = started;
        if (render_base and pending.slice().len != 0) {
            const binding = self.profileTime();
            gl.api.glBindFramebuffer(c.GL_FRAMEBUFFER, self.targets[target].framebuffer);
            if (self.profiling) self.last.target_us += self.profileTime() - binding;
            const surface = render.Surface{ .sink = .{ .context = self, .clip = setClip, .fill = fill, .mask = mask, .texture = artwork } };
            surface.renderDamage(&plan.base, &pending);
            self.flush();
            try self.check();
        }
        if (render_atlas) {
            gl.api.glBindFramebuffer(c.GL_FRAMEBUFFER, self.overlays[target].framebuffer);
            gl.api.glDisable(c.GL_SCISSOR_TEST);
            gl.api.glClearColor(0, 0, 0, 0);
            gl.api.glClear(c.GL_COLOR_BUFFER_BIT);
            self.gpu_pending = true;
            (render.Surface{ .sink = .{ .context = self, .clip = setClip, .fill = fill, .mask = mask, .texture = artwork } }).render(&plan.atlas);
            self.flush();
            try self.check();
        }
        if (self.profiling) submitted = std.Io.Timestamp.now(io, .awake);
        try self.finishGpu(io);
        try self.check();
        const completed = std.Io.Timestamp.now(io, .awake);
        self.last_work_us = scene_started.durationTo(completed).toMicroseconds();
        self.render_total_us += started.durationTo(completed).toMicroseconds();
        if (self.profiling) {
            self.last.submit_us = started.durationTo(submitted).toMicroseconds();
            self.last.complete_us = submitted.durationTo(completed).toMicroseconds();
        }
        if (!self.started) {
            try self.presenter.?.start(target, target, selection);
            self.started = true;
            self.frames += 1;
            self.front = target;
            self.selection = selection;
            self.cache.touch(target);
        } else {
            try self.presenter.?.queue(io, target, target, selection);
            self.queued_target = target;
        }
        self.queued_selection = selection;
        self.submitted_us = completed.toMicroseconds();
        if (render_base) self.cache.base[target] = next;
        if (render_atlas) self.cache.atlas[target] = atlas_next;
    }

    fn check(self: *Display) !void {
        if (self.failure) |failure| return failure;
        const err = gl.api.glGetError();
        if (err != 0) {
            std.log.info("GPU error 0x{x}", .{err});
            self.failure = error.GpuOperation;
            return error.GpuOperation;
        }
    }

    fn sampling() void {
        gl.api.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        gl.api.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        gl.api.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        gl.api.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
    }

    fn resident(self: *Display, key: u64, kind: u8, w: u16, h: u16, data: *const anyopaque) !c_uint {
        if (self.texture_cache.find(key, kind)) |handle| return handle;
        const bytes = @as(usize, w) * h * @as(usize, if (kind == 1) 1 else 4);
        if (w == 0 or h == 0 or w > 4096 or h > 4096 or bytes > texture_cache.byte_budget) return error.TextureTooLarge;
        self.flush(); // Never evict a texture referenced by queued vertices.
        var target = self.texture_cache.victim();
        if (self.texture_cache.entries[target].handle != 0) self.evict(target);
        while (self.texture_cache.bytes + bytes > texture_cache.byte_budget) self.evict(self.texture_cache.oldest().?);
        target = self.texture_cache.victim();
        var handle: c_uint = 0;
        gl.api.glGenTextures(1, &handle);
        gl.api.glBindTexture(c.GL_TEXTURE_2D, handle);
        sampling();
        const format: c_uint = if (kind == 1) c.GL_ALPHA else c.GL_RGBA;
        gl.api.glTexImage2D(c.GL_TEXTURE_2D, 0, @intCast(format), w, h, 0, format, c.GL_UNSIGNED_BYTE, data);
        if (self.profiling) self.last.upload_bytes += bytes;
        self.texture_cache.insert(target, handle, key, kind, bytes);
        try self.check();
        return handle;
    }

    fn evict(self: *Display, index: usize) void {
        const old = self.texture_cache.remove(index);
        if (old.handle != 0) gl.api.glDeleteTextures(1, &old.handle);
        if (self.profiling and old.handle != 0) self.last.texture_evictions += 1;
    }

    fn profileTime(self: *const Display) i64 {
        return if (self.profiling) std.Io.Timestamp.now(self.profile_io.?, .awake).toMicroseconds() else 0;
    }

    fn flush(self: *Display) void {
        if (self.vertex_count == 0 or self.failure != null) return;
        if (self.vertex_count == 6 and self.batch.len == 0 and self.vertices[0].rgba[3] == 255) {
            const first = self.vertices[0];
            const last = self.vertices[5];
            const left = pixelCoordinate(first.x, 512);
            const top = pixelCoordinate(first.y, 384);
            const right = pixelCoordinate(last.x, 512);
            const bottom = pixelCoordinate(last.y, 384);
            self.vertex_count = 0;
            self.clearRect(.{ .x = left, .y = top, .width = right - left, .height = bottom - top }, .{ .r = first.rgba[0], .g = first.rgba[1], .b = first.rgba[2] });
            return;
        }
        const state_started = self.profileTime();
        gl.api.glUseProgram(self.program);
        gl.api.glUniform1f(self.kind_uniform, @floatFromInt(self.batch_kind));
        for (self.batch.textures[0..self.batch.len], 0..) |texture, index| {
            gl.api.glActiveTexture(c.GL_TEXTURE0 + @as(c_uint, @intCast(index)));
            gl.api.glBindTexture(c.GL_TEXTURE_2D, texture);
        }
        gl.api.glActiveTexture(c.GL_TEXTURE0);
        const drawing = self.profileTime();
        gl.api.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(self.vertex_count));
        self.gpu_pending = true;
        if (self.profiling) {
            self.last.draw_calls += 1;
            self.last.draw_state_us += drawing - state_started;
            self.last.draw_us += self.profileTime() - drawing;
        }
        self.vertex_count = 0;
        self.batch.len = 0;
    }

    fn finishGpu(self: *Display, io: std.Io) !void {
        if (!self.gpu_pending) return;
        try self.completion.?.finish(io, self.display, if (self.profiling) &self.last else null);
        self.gpu_pending = false;
    }

    fn rect(self: *Display, x: f32, y: f32, w: f32, h: f32, color: ui.Color, alpha: u8, kind: u8, texture: c_uint, tex: [4]f32) void {
        if (w <= 0 or h <= 0 or self.failure != null) return;
        if (self.clips.len == 0) return self.rectPart(x, y, w, h, color, alpha, kind, texture, tex);
        for (self.clips) |clip| {
            const left = @max(x, @as(f32, @floatFromInt(clip.x)));
            const top = @max(y, @as(f32, @floatFromInt(clip.y)));
            const right = @min(x + w, @as(f32, @floatFromInt(@as(u32, clip.x) + clip.width)));
            const bottom = @min(y + h, @as(f32, @floatFromInt(@as(u32, clip.y) + clip.height)));
            if (left >= right or top >= bottom) continue;
            self.rectPart(left, top, right - left, bottom - top, color, alpha, kind, texture, .{
                tex[0] + (left - x) / w * tex[2], tex[1] + (top - y) / h * tex[3],
                (right - left) / w * tex[2],      (bottom - top) / h * tex[3],
            });
        }
    }

    fn setClip(context: *anyopaque, clips: []const ui.Rect) void {
        const self: *Display = @ptrCast(@alignCast(context));
        self.clips = clips;
    }

    fn rectPart(self: *Display, x: f32, y: f32, w: f32, h: f32, color: ui.Color, alpha: u8, kind: u8, texture: c_uint, tex: [4]f32) void {
        const batch_kind: u8 = if (kind >= 2) kind else 1;
        if (self.batch_kind != batch_kind or self.vertex_count + 6 > self.vertices.len) self.flush();
        const slot: f32 = if (kind == 0) -1 else @floatFromInt(self.batch.slot(texture) orelse blk: {
            self.flush();
            break :blk self.batch.slot(texture).?;
        });
        self.batch_kind = batch_kind;
        const corners = [6][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 } };
        for (corners) |uv| {
            self.vertices[self.vertex_count] = .{
                .x = (x + uv[0] * w) / 512 - 1,
                .y = (y + uv[1] * h) / 384 - 1,
                .u = tex[0] + uv[0] * tex[2],
                .v = tex[1] + uv[1] * tex[3],
                .rgba = .{ color.r, color.g, color.b, alpha },
                .slot = slot,
            };
            self.vertex_count += 1;
        }
    }

    fn fill(context: *anyopaque, bounds: ui.Rect, color: ui.Color, alpha: u8) void {
        const self: *Display = @ptrCast(@alignCast(context));
        if (alpha == 255 and @as(usize, bounds.width) * bounds.height >= 8192) {
            if (self.clips.len == 0) return self.clear(bounds, color);
            for (self.clips) |clip| if (damage.intersection(bounds, clip)) |part| self.clear(part, color);
            return;
        }
        self.rect(@floatFromInt(bounds.x), @floatFromInt(bounds.y), @floatFromInt(bounds.width), @floatFromInt(bounds.height), color, alpha, 0, 0, .{ 0, 0, 1, 1 });
    }

    fn clear(self: *Display, bounds: ui.Rect, color: ui.Color) void {
        self.flush();
        self.clearRect(bounds, color);
    }

    fn clearRect(self: *Display, bounds: ui.Rect, color: ui.Color) void {
        const clearing = self.profileTime();
        gl.api.glEnable(c.GL_SCISSOR_TEST);
        gl.api.glScissor(bounds.x, bounds.y, bounds.width, bounds.height);
        gl.api.glClearColor(@as(f32, @floatFromInt(color.r)) / 255, @as(f32, @floatFromInt(color.g)) / 255, @as(f32, @floatFromInt(color.b)) / 255, 1);
        gl.api.glClear(c.GL_COLOR_BUFFER_BIT);
        gl.api.glDisable(c.GL_SCISSOR_TEST);
        self.gpu_pending = true;
        if (self.profiling) {
            self.last.clear_calls += 1;
            self.last.clear_us += self.profileTime() - clearing;
        }
    }

    fn mask(context: *anyopaque, identity: u64, x: u16, y: u16, pixels: []const u8, w: u16, h: u16, color: u32) void {
        if (w == 0 or h == 0) return;
        const self: *Display = @ptrCast(@alignCast(context));
        const texture = self.resident(identity, 1, w, h, pixels.ptr) catch |err| {
            self.failure = err;
            return;
        };
        self.rect(@floatFromInt(x), @floatFromInt(y), @floatFromInt(w), @floatFromInt(h), @bitCast(color), 255, 1, texture, .{ 0, 0, 1, 1 });
    }
    fn artwork(context: *anyopaque, source: assets.Texture, bounds: ui.Rect, dim: u8, tilt: i16, clip_left: u16) void {
        const self: *Display = @ptrCast(@alignCast(context));
        const texture = self.resident(@intFromPtr(source.pixels.ptr), 2, source.width, source.height, source.pixels.ptr) catch |err| {
            self.failure = err;
            return;
        };
        const x: f32 = @floatFromInt(@as(i32, bounds.x) - clip_left);
        const y: f32 = @floatFromInt(bounds.y);
        const w: f32 = @floatFromInt(bounds.width);
        const h: f32 = @floatFromInt(bounds.height);
        self.flush();
        gl.api.glUseProgram(self.program);
        gl.api.glUniform4f(self.bounds_uniform, x, y, w, h);
        gl.api.glUniform4f(self.crop_uniform, @floatFromInt(source.content_x), @floatFromInt(source.content_y), @floatFromInt(source.content_width), @floatFromInt(source.content_height));
        gl.api.glUniform2f(self.size_uniform, @floatFromInt(source.width), @floatFromInt(source.height));
        gl.api.glUniform2f(self.art_uniform, @as(f32, @floatFromInt(dim)) / 255, @floatFromInt(tilt));
        self.rect(x, y, w, h, @import("artwork_colors.zig").deep, 255, 2, texture, .{ 0, 0, 1, 1 });
        self.flush();
    }

    // Diagnostic oracle only. Normal rendering never maps or reads scanout.
    pub fn verify(self: *Display, expected: []const u32) !void {
        if (self.inFlight()) return error.FramePending;
        const target = &self.targets[self.front];
        const overlay = &self.overlays[self.front];
        var map = c.struct_drm_mode_map_dumb{ .handle = target.buffer.handle, .pad = 0, .offset = 0 };
        if (c.ioctl(self.fd, c.DRM_IOCTL_MODE_MAP_DUMB, &map) != 0) return error.BufferMap;
        const memory = c.mmap(null, @intCast(target.buffer.size), c.PROT_READ, c.MAP_SHARED, self.fd, @intCast(map.offset));
        if (memory == null or memory == c.MAP_FAILED) return error.BufferMap;
        defer _ = c.munmap(memory, @intCast(target.buffer.size));
        var overlay_map = c.struct_drm_mode_map_dumb{ .handle = overlay.buffer.handle, .pad = 0, .offset = 0 };
        if (c.ioctl(self.fd, c.DRM_IOCTL_MODE_MAP_DUMB, &overlay_map) != 0) return error.BufferMap;
        const overlay_memory = c.mmap(null, @intCast(overlay.buffer.size), c.PROT_READ, c.MAP_SHARED, self.fd, @intCast(overlay_map.offset));
        if (overlay_memory == null or overlay_memory == c.MAP_FAILED) return error.BufferMap;
        defer _ = c.munmap(overlay_memory, @intCast(overlay.buffer.size));
        var sync = c.struct_dma_buf_sync{ .flags = c.DMA_BUF_SYNC_START | c.DMA_BUF_SYNC_READ };
        if (c.ioctl(target.prime, c.DMA_BUF_IOCTL_SYNC, &sync) != 0) return error.BufferSync;
        defer {
            sync.flags = c.DMA_BUF_SYNC_END | c.DMA_BUF_SYNC_READ;
            _ = c.ioctl(target.prime, c.DMA_BUF_IOCTL_SYNC, &sync);
        }
        var overlay_sync = c.struct_dma_buf_sync{ .flags = c.DMA_BUF_SYNC_START | c.DMA_BUF_SYNC_READ };
        if (c.ioctl(overlay.prime, c.DMA_BUF_IOCTL_SYNC, &overlay_sync) != 0) return error.BufferSync;
        defer {
            overlay_sync.flags = c.DMA_BUF_SYNC_END | c.DMA_BUF_SYNC_READ;
            _ = c.ioctl(overlay.prime, c.DMA_BUF_IOCTL_SYNC, &overlay_sync);
        }
        const pixels: [*]volatile u32 = @ptrCast(@alignCast(memory.?));
        const overlay_pixels: [*]volatile u32 = @ptrCast(@alignCast(overlay_memory.?));
        for (expected, 0..) |want, i| {
            const x = i % width;
            const y = i / width;
            var actual = pixels[y * (target.buffer.pitch / 4) + x];
            if (self.selection) |selection| if (x >= selection.x and x < @as(usize, selection.x) + selection.width and y >= selection.y and y < @as(usize, selection.y) + selection.height) {
                const layer = overlay_pixels[y * (overlay.buffer.pitch / 4) + x];
                if (layer >> 24 != 0) actual = layer;
            };
            inline for (.{ 0, 8, 16 }) |shift| {
                const delta = @as(i32, @intCast((actual >> shift) & 255)) - @as(i32, @intCast((want >> shift) & 255));
                if (@abs(delta) > 2) {
                    _ = c.usleep(10000);
                    const delayed = pixels[(i / width) * (target.buffer.pitch / 4) + i % width];
                    std.log.err("GPU pixel mismatch ({d},{d}) actual={x} after10ms={x} expected={x}", .{ x, y, actual, delayed, want });
                    return error.GpuPixelMismatch;
                }
            }
        }
    }

    pub fn close(self: *Display) void {
        if (self.presenter) |*presenter| presenter.deinit();
        if (self.context != null) {
            for (self.texture_cache.entries) |entry| if (entry.handle != 0) {
                gl.api.glDeleteTextures(1, &entry.handle);
            };
            if (self.program != 0) gl.api.glDeleteProgram(self.program);
            for (&self.targets) |*target| {
                if (target.framebuffer != 0) gl.api.glDeleteFramebuffers(1, &target.framebuffer);
                if (target.texture != 0) gl.api.glDeleteTextures(1, &target.texture);
                if (target.image != null) _ = self.image_destroy.?(self.display, target.image);
            }
            for (&self.overlays) |*target| {
                if (target.framebuffer != 0) gl.api.glDeleteFramebuffers(1, &target.framebuffer);
                if (target.texture != 0) gl.api.glDeleteTextures(1, &target.texture);
                if (target.image != null) _ = self.image_destroy.?(self.display, target.image);
            }
            _ = gl.api.eglMakeCurrent(self.display, null, null, null);
            _ = gl.api.eglDestroyContext(self.display, self.context);
        }
        if (self.surface != null) _ = gl.api.eglDestroySurface(self.display, self.surface);
        if (self.display != null) _ = gl.api.eglTerminate(self.display);
        for (&self.targets) |*target| {
            if (target.prime >= 0) _ = c.close(target.prime);
            if (target.buffer.handle != 0) {
                var destroy = c.struct_drm_mode_destroy_dumb{ .handle = target.buffer.handle };
                _ = c.ioctl(self.fd, c.DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
            }
        }
        for (&self.overlays) |*target| {
            if (target.prime >= 0) _ = c.close(target.prime);
            if (target.buffer.handle != 0) {
                var destroy = c.struct_drm_mode_destroy_dumb{ .handle = target.buffer.handle };
                _ = c.ioctl(self.fd, c.DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
            }
        }
        if (self.fd >= 0) _ = c.close(self.fd);
        if (self.frames != 0) std.log.info("GPU session: frames={d} mean_render_us={d} resident_texture_bytes={d}", .{ self.frames, @divTrunc(self.render_total_us, @as(i64, @intCast(self.frames))), self.texture_cache.bytes });
        std.heap.page_allocator.destroy(self);
    }
};
