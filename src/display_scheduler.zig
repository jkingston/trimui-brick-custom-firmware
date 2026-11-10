// SPDX-License-Identifier: GPL-2.0-only
// The vendor PowerVR userspace aborts on its own qualified DMA-BUF probe with
// the current kernel. Keep product rendering on the stock fbdev scanout path.
const std = @import("std");
const render = @import("render.zig");
const ui = @import("ui_scene.zig");

const framebuffer_path = "/dev/fb0";
const blank_path = "/sys/class/graphics/fb0/blank";
const virtual_size_path = "/sys/class/graphics/fb0/virtual_size";
const bits_path = "/sys/class/graphics/fb0/bits_per_pixel";
const stride_path = "/sys/class/graphics/fb0/stride";
const fb_io_get_variable_screen_info: u32 = 0x4600;
const fb_io_pan_display: u32 = 0x4606;
const fb_activate_vertical_blank: u32 = 16;

const FbBitfield = extern struct { offset: u32, length: u32, msb_right: u32 };
const FbVarScreeninfo = extern struct {
    xres: u32,
    yres: u32,
    xres_virtual: u32,
    yres_virtual: u32,
    xoffset: u32,
    yoffset: u32,
    bits_per_pixel: u32,
    grayscale: u32,
    red: FbBitfield,
    green: FbBitfield,
    blue: FbBitfield,
    transp: FbBitfield,
    nonstd: u32,
    activate: u32,
    height: u32,
    width: u32,
    accel_flags: u32,
    pixclock: u32,
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,
    hsync_len: u32,
    vsync_len: u32,
    sync: u32,
    vmode: u32,
    rotate: u32,
    colorspace: u32,
    reserved: [4]u32,
};

comptime {
    if (@sizeOf(FbVarScreeninfo) != 160) @compileError("fb_var_screeninfo ABI mismatch");
}

fn readAttribute(io: std.Io, path: []const u8, buffer: []u8) ![]const u8 {
    return std.mem.trim(u8, try std.Io.Dir.cwd().readFile(io, path, buffer), " \t\r\n");
}

fn writeAttribute(io: std.Io, path: []const u8, value: []const u8) !void {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only });
    defer file.close(io);
    var buffer: [16]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(value);
    try writer.interface.flush();
}

fn closeFd(io: std.Io, fd: std.posix.fd_t) void {
    (std.Io.File{ .handle = fd, .flags = .{ .nonblocking = false } }).close(io);
}

pub const Scheduler = struct {
    io: std.Io,
    fd: std.posix.fd_t,
    memory: []align(std.heap.page_size_min) u8,
    surface: render.Surface,
    variable: FbVarScreeninfo,
    page_count: usize,
    draw_page: usize,
    unblanked: bool = false,
    dirty: bool = false,

    pub fn open(io: std.Io, _: bool) !Scheduler {
        var size_buffer: [64]u8 = undefined;
        const size = try readAttribute(io, virtual_size_path, &size_buffer);
        const comma = std.mem.findScalar(u8, size, ',') orelse return error.InvalidFramebufferGeometry;
        var bits_buffer: [32]u8 = undefined;
        var stride_buffer: [32]u8 = undefined;
        const width = try std.fmt.parseInt(usize, size[0..comma], 10);
        const virtual_height = try std.fmt.parseInt(usize, size[comma + 1 ..], 10);
        const bits = try std.fmt.parseInt(usize, try readAttribute(io, bits_path, &bits_buffer), 10);
        const stride = try std.fmt.parseInt(usize, try readAttribute(io, stride_path, &stride_buffer), 10);
        if (width != render.width or virtual_height < render.height or bits != 32 or stride != render.width * @sizeOf(u32))
            return error.UnsupportedFramebufferGeometry;

        const fd = try std.posix.openat(std.posix.AT.FDCWD, framebuffer_path, .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
        errdefer closeFd(io, fd);
        // SAFETY: a successful FBIOGET_VSCREENINFO initializes every byte.
        var variable: FbVarScreeninfo = undefined;
        if (std.posix.errno(std.os.linux.ioctl(fd, fb_io_get_variable_screen_info, @intFromPtr(&variable))) != .SUCCESS)
            return error.FramebufferInfoFailed;
        if (variable.xres != render.width or variable.yres != render.height or variable.yres_virtual != virtual_height or virtual_height % render.height != 0)
            return error.UnsupportedFramebufferGeometry;
        const page_count = virtual_height / render.height;
        if (page_count < 2 or variable.yoffset % render.height != 0 or variable.yoffset / render.height >= page_count)
            return error.FramebufferPageFlippingUnavailable;
        const draw_page = (variable.yoffset / render.height + 1) % page_count;
        const memory = try std.posix.mmap(null, stride * virtual_height, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
        const pixels: [*]u32 = @ptrCast(@alignCast(memory.ptr));
        return .{
            .io = io,
            .fd = fd,
            .memory = memory,
            .surface = .{ .pixels = pixels[draw_page * render.width * render.height ..][0 .. render.width * render.height] },
            .variable = variable,
            .page_count = page_count,
            .draw_page = draw_page,
        };
    }

    pub fn close(self: *Scheduler) void {
        std.posix.munmap(self.memory);
        closeFd(self.io, self.fd);
    }

    pub fn show(self: *Scheduler, tree: *const ui.Tree) !void {
        try self.present(tree);
    }
    pub fn submit(self: *Scheduler, tree: *const ui.Tree) !void {
        try self.present(tree);
    }

    fn present(self: *Scheduler, tree: *const ui.Tree) !void {
        self.surface.render(tree);
        self.variable.xoffset = 0;
        self.variable.yoffset = @intCast(self.draw_page * render.height);
        self.variable.activate = fb_activate_vertical_blank;
        if (std.posix.errno(std.os.linux.ioctl(self.fd, fb_io_pan_display, @intFromPtr(&self.variable))) != .SUCCESS)
            return error.FramebufferPresentFailed;
        self.draw_page = (self.draw_page + 1) % self.page_count;
        const pixels: [*]u32 = @ptrCast(@alignCast(self.memory.ptr));
        self.surface.pixels = pixels[self.draw_page * render.width * render.height ..][0 .. render.width * render.height];
        self.dirty = false;
        if (!self.unblanked) {
            try writeAttribute(self.io, blank_path, "0\n");
            self.unblanked = true;
        }
    }

    pub fn recordInput(_: *Scheduler, _: i64) void {}
    pub fn requestFrame(self: *Scheduler, _: ?*const ui.Tree) !void {
        self.dirty = true;
    }
    pub fn frameDue(self: *const Scheduler) bool {
        return self.dirty;
    }
    pub fn poll(_: *Scheduler, fds: []std.posix.pollfd, timeout_ms: i32) !usize {
        return std.posix.poll(fds, timeout_ms);
    }
};
