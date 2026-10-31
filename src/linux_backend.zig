// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const model = @import("model.zig");
const render = @import("render.zig");
const ui = @import("ui.zig");

const framebuffer_path = "/dev/fb0";
const blank_path = "/sys/class/graphics/fb0/blank";
const virtual_size_path = "/sys/class/graphics/fb0/virtual_size";
const bits_path = "/sys/class/graphics/fb0/bits_per_pixel";
const stride_path = "/sys/class/graphics/fb0/stride";
const tty_path = "/dev/tty0";
const KDSETMODE: u32 = 0x4b3a;
const KD_TEXT: usize = 0;
const KD_GRAPHICS: usize = 1;

const EV_SYN: u16 = 0x00;
const EV_KEY: u16 = 0x01;
const KEY_F1: u16 = 59;
const KEY_F2: u16 = 60;
const SYN_REPORT: u16 = 0x00;
const SYN_DROPPED: u16 = 0x03;
const BTN_SOUTH: u16 = 0x130;
const BTN_EAST: u16 = 0x131;
const BTN_NORTH: u16 = 0x133;
const BTN_WEST: u16 = 0x134;
const BTN_SELECT: u16 = 0x13a;
const BTN_MODE: u16 = 0x13c;
const BTN_DPAD_UP: u16 = 0x220;
const BTN_DPAD_DOWN: u16 = 0x221;
const BTN_DPAD_LEFT: u16 = 0x222;
const BTN_DPAD_RIGHT: u16 = 0x223;

const InputEvent = extern struct {
    seconds: isize,
    microseconds: isize,
    event_type: u16,
    code: u16,
    value: i32,
};

const Geometry = struct {
    width: usize,
    virtual_height: usize,
    bits_per_pixel: usize,
    stride: usize,

    fn validate(self: Geometry) !void {
        if (self.width != render.width or self.virtual_height < render.height)
            return error.UnsupportedFramebufferGeometry;
        if (self.bits_per_pixel != 32 or self.stride != render.width * @sizeOf(u32))
            return error.UnsupportedFramebufferFormat;
    }
};

fn readAttribute(io: std.Io, path: []const u8, buffer: []u8) ![]const u8 {
    const bytes = try std.Io.Dir.cwd().readFile(io, path, buffer);
    return std.mem.trim(u8, bytes, " \t\r\n");
}

fn parseGeometry(io: std.Io) !Geometry {
    var size_buffer: [64]u8 = undefined;
    const size = try readAttribute(io, virtual_size_path, &size_buffer);
    const comma = std.mem.indexOfScalar(u8, size, ',') orelse return error.InvalidFramebufferGeometry;
    var bits_buffer: [32]u8 = undefined;
    var stride_buffer: [32]u8 = undefined;
    return .{
        .width = try std.fmt.parseInt(usize, size[0..comma], 10),
        .virtual_height = try std.fmt.parseInt(usize, size[comma + 1 ..], 10),
        .bits_per_pixel = try std.fmt.parseInt(usize, try readAttribute(io, bits_path, &bits_buffer), 10),
        .stride = try std.fmt.parseInt(usize, try readAttribute(io, stride_path, &stride_buffer), 10),
    };
}

fn closeFd(io: std.Io, fd: std.posix.fd_t, nonblocking: bool) void {
    (std.Io.File{ .handle = fd, .flags = .{ .nonblocking = nonblocking } }).close(io);
}

fn writeAttribute(io: std.Io, path: []const u8, value: []const u8) !void {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only });
    defer file.close(io);
    var buffer: [16]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(value);
    try writer.interface.flush();
}

const Framebuffer = struct {
    io: std.Io,
    fd: std.posix.fd_t,
    memory: []align(std.heap.page_size_min) u8,
    surface: render.Surface,

    fn open(io: std.Io) !Framebuffer {
        const geometry = try parseGeometry(io);
        try geometry.validate();
        const fd = try std.posix.openat(std.posix.AT.FDCWD, framebuffer_path, .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
        errdefer closeFd(io, fd, false);
        const memory = try std.posix.mmap(null, geometry.stride * render.height, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
        const pixel_pointer: [*]u32 = @ptrCast(@alignCast(memory.ptr));
        return .{
            .io = io,
            .fd = fd,
            .memory = memory,
            .surface = .{ .pixels = pixel_pointer[0 .. render.width * render.height] },
        };
    }

    fn close(self: *Framebuffer) void {
        std.posix.munmap(self.memory);
        closeFd(self.io, self.fd, false);
    }

    fn show(self: *Framebuffer, tree: *const ui.Tree) !void {
        self.surface.render(tree);
        try writeAttribute(self.io, blank_path, "0\n");
    }
};

const Console = struct {
    io: std.Io,
    fd: std.posix.fd_t,

    fn open(io: std.Io) !Console {
        const fd = try std.posix.openat(std.posix.AT.FDCWD, tty_path, .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
        errdefer closeFd(io, fd, false);
        if (std.posix.errno(std.os.linux.ioctl(fd, KDSETMODE, KD_GRAPHICS)) != .SUCCESS)
            return error.ConsoleGraphicsModeFailed;
        return .{ .io = io, .fd = fd };
    }

    fn close(self: *Console) void {
        _ = std.os.linux.ioctl(self.fd, KDSETMODE, KD_TEXT);
        closeFd(self.io, self.fd, false);
    }
};

fn discoverGamepad(io: std.Io) !std.posix.fd_t {
    var index: usize = 0;
    while (index < 32) : (index += 1) {
        var path_buffer: [96]u8 = undefined;
        const name_path = try std.fmt.bufPrint(&path_buffer, "/sys/class/input/event{d}/device/name", .{index});
        var name_buffer: [128]u8 = undefined;
        const name = readAttribute(io, name_path, &name_buffer) catch continue;
        if (!std.mem.eql(u8, name, "TrimUI Brick Gamepad")) continue;
        const event_path = try std.fmt.bufPrint(&path_buffer, "/dev/input/event{d}", .{index});
        return std.posix.openat(std.posix.AT.FDCWD, event_path, .{
            .ACCMODE = .RDONLY,
            .CLOEXEC = true,
            .NONBLOCK = true,
        }, 0);
    }
    return error.GamepadNotFound;
}

fn actionForEvent(event: InputEvent, dropped: *bool) ?model.Action {
    if (event.event_type == EV_SYN and event.code == SYN_DROPPED) {
        dropped.* = true;
        return null;
    }
    if (dropped.*) {
        if (event.event_type == EV_SYN and event.code == SYN_REPORT) dropped.* = false;
        return null;
    }
    if (event.event_type != EV_KEY or (event.value != 1 and event.value != 2)) return null;
    return switch (event.code) {
        BTN_DPAD_UP => .up,
        BTN_DPAD_DOWN => .down,
        BTN_DPAD_LEFT => .left,
        BTN_DPAD_RIGHT => .right,
        BTN_EAST => if (event.value == 1) .confirm else null,
        BTN_SOUTH => if (event.value == 1) .back else null,
        BTN_NORTH => if (event.value == 1) .options else null,
        BTN_WEST => if (event.value == 1) .favorite else null,
        BTN_SELECT => null,
        BTN_MODE => if (event.value == 1) .home else null,
        KEY_F1 => if (event.value == 1) .switcher else null,
        KEY_F2 => null,
        else => null,
    };
}

pub fn run(io: std.Io) !void {
    // Stop fbcon from drawing its text cursor over the product surface.
    var console = try Console.open(io);
    defer console.close();
    var framebuffer = try Framebuffer.open(io);
    defer framebuffer.close();

    var splash_tree = ui.splash();
    try framebuffer.show(&splash_tree);
    try std.Io.sleep(io, .fromMilliseconds(250), .awake);

    var state = model.Model{};
    var tree = state.tree();
    try framebuffer.show(&tree);

    const input_fd = try discoverGamepad(io);
    defer closeFd(io, input_fd, true);
    var poll_fds = [_]std.posix.pollfd{.{ .fd = input_fd, .events = std.posix.POLL.IN, .revents = 0 }};
    var dropped = false;
    var buffer: [32 * @sizeOf(InputEvent)]u8 align(@alignOf(InputEvent)) = undefined;

    while (true) {
        // A static screen has no timer. The process blocks until real input arrives.
        _ = try std.posix.poll(&poll_fds, -1);
        if ((poll_fds[0].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0)
            return error.GamepadDisconnected;
        if ((poll_fds[0].revents & std.posix.POLL.IN) == 0) continue;
        while (true) {
            const bytes_read = std.posix.read(input_fd, &buffer) catch |err| switch (err) {
                error.WouldBlock => break,
                else => return err,
            };
            if (bytes_read == 0) return error.GamepadDisconnected;
            if (bytes_read % @sizeOf(InputEvent) != 0) return error.InvalidInputEvent;
            const events = std.mem.bytesAsSlice(InputEvent, buffer[0..bytes_read]);
            for (events) |event| {
                if (actionForEvent(event, &dropped)) |action| {
                    if (state.apply(action)) {
                        tree = state.tree();
                        try framebuffer.show(&tree);
                    }
                }
            }
            if (bytes_read < buffer.len) break;
        }
    }
}

test "navigation repeats and dropped streams resynchronise" {
    const testing = std.testing;
    var dropped = false;
    try testing.expectEqual(model.Action.down, actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = EV_KEY, .code = BTN_DPAD_DOWN, .value = 1 }, &dropped).?);
    try testing.expectEqual(model.Action.down, actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = EV_KEY, .code = BTN_DPAD_DOWN, .value = 2 }, &dropped).?);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = EV_KEY, .code = BTN_EAST, .value = 2 }, &dropped) == null);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = EV_SYN, .code = SYN_DROPPED, .value = 0 }, &dropped) == null);
    try testing.expect(dropped);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = EV_KEY, .code = BTN_EAST, .value = 1 }, &dropped) == null);
    _ = actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = EV_SYN, .code = 0, .value = 0 }, &dropped);
    try testing.expect(!dropped);
}
