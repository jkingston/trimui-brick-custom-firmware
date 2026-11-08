// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const bluetooth = @import("bluetooth.zig");
const catalog = @import("catalog.zig");
const captive = @import("captive.zig");
const input_repeat = @import("input_repeat.zig");
const model = @import("model.zig");
const overlay = @import("overlay.zig");
const render = @import("render.zig");
const retroarch = @import("retroarch.zig");
const ui = @import("ui.zig");
const settings = @import("settings.zig");
const bluetooth_ipc = @import("bluetooth_ipc.zig");
const wifi_ipc = @import("wifi_ipc.zig");

const framebuffer_path = "/dev/fb0";
const blank_path = "/sys/class/graphics/fb0/blank";
const virtual_size_path = "/sys/class/graphics/fb0/virtual_size";
const bits_path = "/sys/class/graphics/fb0/bits_per_pixel";
const stride_path = "/sys/class/graphics/fb0/stride";
const tty_path = "/dev/tty0";
const kd_set_mode: u32 = 0x4b3a;
const kd_text: usize = 0;
const kd_graphics: usize = 1;
const fb_io_get_variable_screen_info: u32 = 0x4600;
const fb_io_pan_display: u32 = 0x4606;
const fb_activate_vertical_blank: u32 = 16;

const ev_syn: u16 = 0x00;
const ev_key: u16 = 0x01;
const ev_abs: u16 = 0x03;
const syn_report: u16 = 0x00;
const syn_dropped: u16 = 0x03;
const btn_south: u16 = 0x130;
const btn_east: u16 = 0x131;
const btn_mode: u16 = 0x13c;
const btn_view: u16 = 0x2c0;
const btn_filter: u16 = 0x2c1;
const btn_dpad_up: u16 = 0x220;
const btn_dpad_down: u16 = 0x221;
const btn_dpad_left: u16 = 0x222;
const btn_dpad_right: u16 = 0x223;
const abs_hat0_x: u16 = 0x10;
const abs_hat0_y: u16 = 0x11;

const InputEvent = extern struct {
    seconds: isize,
    microseconds: isize,
    event_type: u16,
    code: u16,
    value: i32,
};

const FbBitfield = extern struct {
    offset: u32,
    length: u32,
    msb_right: u32,
};

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
    const comma = std.mem.findScalar(u8, size, ',') orelse return error.InvalidFramebufferGeometry;
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
    variable: FbVarScreeninfo,
    page_count: usize,
    draw_page: usize,
    unblanked: bool = false,
    background: ?[]u32 = null,

    fn open(io: std.Io) !Framebuffer {
        const geometry = try parseGeometry(io);
        try geometry.validate();
        const fd = try std.posix.openat(std.posix.AT.FDCWD, framebuffer_path, .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
        errdefer closeFd(io, fd, false);
        // SAFETY: a successful FBIOGET_VSCREENINFO call initializes every byte.
        var variable: FbVarScreeninfo = undefined;
        if (std.posix.errno(std.os.linux.ioctl(fd, fb_io_get_variable_screen_info, @intFromPtr(&variable))) != .SUCCESS)
            return error.FramebufferInfoFailed;
        if (variable.xres != render.width or variable.yres != render.height or
            variable.yres_virtual != geometry.virtual_height or geometry.virtual_height % render.height != 0)
            return error.UnsupportedFramebufferGeometry;
        const page_count = geometry.virtual_height / render.height;
        if (page_count < 2 or variable.yoffset % render.height != 0 or variable.yoffset / render.height >= page_count)
            return error.FramebufferPageFlippingUnavailable;
        const display_page = variable.yoffset / render.height;
        const draw_page = (display_page + 1) % page_count;
        const memory = try std.posix.mmap(null, geometry.stride * geometry.virtual_height, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
        const pixel_pointer: [*]u32 = @ptrCast(@alignCast(memory.ptr));
        return .{
            .io = io,
            .fd = fd,
            .memory = memory,
            .surface = .{ .pixels = pixel_pointer[draw_page * render.width * render.height ..][0 .. render.width * render.height] },
            .variable = variable,
            .page_count = page_count,
            .draw_page = draw_page,
        };
    }

    fn close(self: *Framebuffer) void {
        if (self.background) |background| std.heap.page_allocator.free(background);
        std.posix.munmap(self.memory);
        closeFd(self.io, self.fd, false);
    }

    fn show(self: *Framebuffer, tree: *const ui.Tree) !void {
        if (tree.preserve_background) {
            if (self.background) |background| @memcpy(self.surface.pixels, background);
        }
        self.surface.render(tree);
        self.variable.xoffset = 0;
        self.variable.yoffset = @intCast(self.draw_page * render.height);
        self.variable.activate = fb_activate_vertical_blank;
        if (std.posix.errno(std.os.linux.ioctl(self.fd, fb_io_pan_display, @intFromPtr(&self.variable))) != .SUCCESS)
            return error.FramebufferPresentFailed;
        self.draw_page = (self.draw_page + 1) % self.page_count;
        const pixel_pointer: [*]u32 = @ptrCast(@alignCast(self.memory.ptr));
        self.surface.pixels = pixel_pointer[self.draw_page * render.width * render.height ..][0 .. render.width * render.height];
        if (!self.unblanked) {
            try writeAttribute(self.io, blank_path, "0\n");
            self.unblanked = true;
        }
    }

    fn captureBackground(self: *Framebuffer) !void {
        const display_page = self.variable.yoffset / render.height;
        const pixel_pointer: [*]u32 = @ptrCast(@alignCast(self.memory.ptr));
        const displayed = pixel_pointer[display_page * render.width * render.height ..][0 .. render.width * render.height];
        const background = try std.heap.page_allocator.alloc(u32, render.width * render.height);
        @memcpy(background, displayed);
        self.background = background;
    }
};

const Console = struct {
    io: std.Io,
    fd: std.posix.fd_t,

    fn open(io: std.Io) !Console {
        const fd = try std.posix.openat(std.posix.AT.FDCWD, tty_path, .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
        errdefer closeFd(io, fd, false);
        if (std.posix.errno(std.os.linux.ioctl(fd, kd_set_mode, kd_graphics)) != .SUCCESS)
            return error.ConsoleGraphicsModeFailed;
        return .{ .io = io, .fd = fd };
    }

    fn close(self: *Console) void {
        _ = std.os.linux.ioctl(self.fd, kd_set_mode, kd_text);
        closeFd(self.io, self.fd, false);
    }
};

const max_gamepads = 8;
const input_directory = "/dev/input";
const Gamepad = struct {
    fd: std.posix.fd_t = -1,
    event_index: u8 = 255,
    builtin: bool = false,
    dropped: bool = false,
};

/// Linux exposes input capability bitmaps most-significant word first. Reading
/// from the final hex digit makes this independent of the target word size.
fn capabilityHas(bitmap: []const u8, bit: usize) bool {
    const nibble = bit / 4;
    const shift: u3 = @intCast(bit % 4);
    var seen: usize = 0;
    var cursor = bitmap.len;
    while (cursor != 0) {
        cursor -= 1;
        const byte = bitmap[cursor];
        if (std.ascii.isWhitespace(byte)) continue;
        const value = std.fmt.charToDigit(byte, 16) catch return false;
        if (seen == nibble) return (value & (@as(u8, 1) << shift)) != 0;
        seen += 1;
    }
    return false;
}

const Gamepads = struct {
    slots: [max_gamepads]Gamepad = @splat(.{}),

    fn close(self: *Gamepads, io: std.Io) void {
        for (&self.slots) |*slot| if (slot.fd >= 0) {
            closeFd(io, slot.fd, true);
            slot.* = .{};
        };
    }

    fn hasIndex(self: *const Gamepads, index: u8) bool {
        for (self.slots) |slot| if (slot.fd >= 0 and slot.event_index == index) return true;
        return false;
    }

    fn rescan(self: *Gamepads, io: std.Io) !bool {
        var present: [64]bool = @splat(false);
        var changed = false;
        for (0..64) |raw_index| {
            var path_buffer: [128]u8 = undefined;
            const name_path = try std.fmt.bufPrint(&path_buffer, "/sys/class/input/event{d}/device/name", .{raw_index});
            var name_buffer: [128]u8 = undefined;
            const name = readAttribute(io, name_path, &name_buffer) catch continue;
            var capability_buffer: [1024]u8 = undefined;
            const capability_path = try std.fmt.bufPrint(&path_buffer, "/sys/class/input/event{d}/device/capabilities/key", .{raw_index});
            const capabilities = readAttribute(io, capability_path, &capability_buffer) catch continue;
            const builtin = std.mem.eql(u8, name, "TrimUI Brick Gamepad");
            if (!builtin and !capabilityHas(capabilities, btn_south)) continue;
            present[raw_index] = true;
            const index: u8 = @intCast(raw_index);
            if (self.hasIndex(index)) continue;
            for (&self.slots) |*slot| if (slot.fd < 0) {
                const event_path = try std.fmt.bufPrint(&path_buffer, "/dev/input/event{d}", .{raw_index});
                const fd = std.posix.openat(std.posix.AT.FDCWD, event_path, .{
                    .ACCMODE = .RDONLY,
                    .CLOEXEC = true,
                    .NONBLOCK = true,
                }, 0) catch break;
                slot.* = .{ .fd = fd, .event_index = index, .builtin = builtin };
                changed = true;
                break;
            };
        }
        for (&self.slots) |*slot| if (slot.fd >= 0 and !present[slot.event_index]) {
            closeFd(io, slot.fd, true);
            slot.* = .{};
            changed = true;
        };
        return changed;
    }

    fn hasBuiltin(self: *const Gamepads) bool {
        for (self.slots) |slot| if (slot.fd >= 0 and slot.builtin) return true;
        return false;
    }
};

fn openInputMonitor() !std.posix.fd_t {
    const raw = std.os.linux.inotify_init1(std.os.linux.IN.CLOEXEC | std.os.linux.IN.NONBLOCK);
    if (std.posix.errno(raw) != .SUCCESS) return error.InputMonitorUnavailable;
    const fd: std.posix.fd_t = @intCast(raw);
    errdefer _ = std.os.linux.close(fd);
    const watch = std.os.linux.inotify_add_watch(fd, input_directory, std.os.linux.IN.CREATE | std.os.linux.IN.DELETE | std.os.linux.IN.MOVED_TO | std.os.linux.IN.MOVED_FROM | std.os.linux.IN.ATTRIB);
    if (std.posix.errno(watch) != .SUCCESS) return error.InputMonitorUnavailable;
    return fd;
}

fn drainInputMonitor(fd: std.posix.fd_t) void {
    var events: [1024]u8 = undefined;
    while (true) {
        const result = std.os.linux.read(fd, &events, events.len);
        if (std.posix.errno(result) != .SUCCESS or result == 0) return;
        if (result < events.len) return;
    }
}

fn actionForEvent(event: InputEvent, builtin: bool, dropped: *bool) ?model.Action {
    if (event.event_type == ev_syn and event.code == syn_dropped) {
        dropped.* = true;
        return null;
    }
    if (dropped.*) {
        if (event.event_type == ev_syn and event.code == syn_report) dropped.* = false;
        return null;
    }
    if (event.event_type == ev_abs and event.value != 0) return switch (event.code) {
        abs_hat0_x => if (event.value < 0) .left else .right,
        abs_hat0_y => if (event.value < 0) .up else .down,
        else => null,
    };
    if (event.event_type != ev_key or event.value != 1) return null;
    return switch (event.code) {
        btn_dpad_up => .up,
        btn_dpad_down => .down,
        btn_dpad_left => .left,
        btn_dpad_right => .right,
        btn_east => if (builtin) .select else .back,
        btn_south => if (builtin) .back else .select,
        btn_mode => .menu,
        btn_view => .view,
        btn_filter => .filter,
        else => null,
    };
}

fn directionForEvent(event: InputEvent) ?model.Action {
    if (event.event_type == ev_abs) return switch (event.code) {
        abs_hat0_x => if (event.value < 0) .left else .right,
        abs_hat0_y => if (event.value < 0) .up else .down,
        else => null,
    };
    if (event.event_type != ev_key) return null;
    const code = event.code;
    return switch (code) {
        btn_dpad_up => .up,
        btn_dpad_down => .down,
        btn_dpad_left => .left,
        btn_dpad_right => .right,
        else => null,
    };
}

fn nowMilliseconds(io: std.Io) i64 {
    return std.Io.Timestamp.now(io, .awake).toMilliseconds();
}

fn observeRepeat(repeat: *input_repeat.Controller, event: InputEvent, now_ms: i64) void {
    if (event.event_type == ev_syn and event.code == syn_dropped) {
        repeat.reset();
        return;
    }
    const action = directionForEvent(event) orelse return;
    switch (event.value) {
        0 => repeat.release(action),
        1 => repeat.press(action, now_ms),
        else => {},
    }
}

fn repeatAllowed(state: *const model.Model, action: model.Action) bool {
    return action == .up or action == .down or
        (state.page == .games and (action == .left or action == .right));
}

const SessionAction = struct { changed: bool = false, launch: ?usize = null };

fn saveLibraryPreferences(io: std.Io, state: *const model.Model) void {
    const dir = std.Io.Dir.cwd().openDir(io, "/data/settings", .{}) catch return;
    defer dir.close(io);
    @import("library_preferences.zig").save(io, dir, state) catch |err|
        std.log.warn("Could not save library preferences: {s}", .{@errorName(err)});
}

fn sendBluetooth(client: ?*bluetooth_ipc.Client, next_request: *u32, command: *bluetooth.Command) bool {
    command.request_id = next_request.*;
    next_request.* +%= 1;
    if (next_request.* == 0) next_request.* = 1;
    if (client) |connected| {
        connected.send(command) catch return false;
        return true;
    }
    command.wipe();
    return false;
}

fn wifiChanging(state: *const model.Model) bool {
    for (state.wifi.wifi_state.snapshot.items()) |network| switch (network.state) {
        .connecting, .validating, .reconnecting => return true,
        else => {},
    };
    return state.wifi.wifi_state.snapshot.radio == .starting or state.wifi.wifi_state.snapshot.radio == .stopping;
}

fn applySessionAction(io: std.Io, state: *model.Model, framebuffer: *Framebuffer, wifi_client: ?*wifi_ipc.Client, bluetooth_client: ?*bluetooth_ipc.Client, bluetooth_request: *u32, action: model.Action) !SessionAction {
    if (!state.apply(action)) return .{};
    state.notice = "";
    if (state.takeSetting()) |setting|
        settings.apply(io, state.settings, setting) catch {
            state.settings = settings.load(io);
            state.notice = "Could not apply setting";
        };
    if (state.takeWifiRequest()) |pending| {
        var request = pending;
        if (wifi_client) |client| client.send(&request) catch {
            state.notice = "Wi-Fi service is unavailable";
        } else {
            request.wipe();
            state.notice = "Wi-Fi service is unavailable";
        }
    }
    if (state.takeBluetoothCommand()) |pending| {
        var command = pending;
        if (!sendBluetooth(bluetooth_client, bluetooth_request, &command))
            state.notice = "Bluetooth service is unavailable";
    }
    if (state.pending_power) |command| {
        state.pending_power = null;
        saveLibraryPreferences(io, state);
        var status = ui.message(state.settings.appearance.colors(), "Power", switch (command) {
            .screen_off => "",
            .suspend_device => "Going to sleep…",
            .shutdown => "Shutting down…",
        }, "");
        try framebuffer.show(&status);
        performPower(io, command) catch {
            state.notice = if (command == .suspend_device) "Unable to sleep. The device is still awake." else "Could not complete power action";
        };
        state.page = .home;
        state.selected = 0;
    }
    if (state.takeLaunch()) |index| {
        var launching = ui.gameDetail(state.settings.appearance.colors(), state.games[index], null);
        try framebuffer.show(&launching);
        saveLibraryPreferences(io, state);
        return .{ .launch = index };
    }
    return .{ .changed = true };
}

fn refreshCaptive(io: std.Io, state: *model.Model) bool {
    var next = captive.status(io);
    if (next.url_len != 0) captive.ensureQr(io, &next);
    const changed = next.generation != state.wifi_fallback.generation or
        next.state != state.wifi_fallback.state or
        !std.mem.eql(u8, next.url(), state.wifi_fallback.url()) or
        next.qr.width != state.wifi_fallback.qr.width;
    if (changed) state.wifi_fallback = next;
    return changed;
}

fn runSession(io: std.Io, state: *model.Model, wifi_only: bool) !?usize {
    // Stop fbcon from drawing its text cursor over the product surface.
    var console = try Console.open(io);
    defer console.close();
    var framebuffer = try Framebuffer.open(io);
    defer framebuffer.close();

    state.battery_percent = batteryPercent(io);
    var battery_deadline = nowMilliseconds(io) + 60000;
    var tree = state.tree();
    try framebuffer.show(&tree);

    var wifi_client: ?wifi_ipc.Client = wifi_ipc.Client.connect("/run/brick-wifi/control.sock") catch null;
    defer if (wifi_client) |client| client.close();
    var wifi_reconnect_deadline = nowMilliseconds(io) + 1000;
    var bluetooth_client: ?bluetooth_ipc.Client = bluetooth_ipc.Client.connect("/run/brick-bluetooth/control.sock") catch null;
    defer if (bluetooth_client) |client| client.close();
    var bluetooth_reconnect_deadline = nowMilliseconds(io) + 1000;
    var bluetooth_request: u32 = 1;
    var network_changing = false;
    var captive_deadline = nowMilliseconds(io);

    var gamepads = Gamepads{};
    defer gamepads.close(io);
    _ = try gamepads.rescan(io);
    if (!gamepads.hasBuiltin()) return error.GamepadNotFound;
    const input_monitor = try openInputMonitor();
    defer closeFd(io, input_monitor, true);
    var input_rescan_deadline = nowMilliseconds(io) + 1000;
    var poll_fds: [max_gamepads + 3]std.posix.pollfd = @splat(.{ .fd = -1, .events = std.posix.POLL.IN, .revents = 0 });
    var repeat: input_repeat.Controller = .{};
    var motion: @import("shelf_motion.zig").Motion = .{};
    var was_animating = false;
    var save_deadline: ?i64 = null;
    var buffer: [32 * @sizeOf(InputEvent)]u8 align(@alignOf(InputEvent)) = undefined;

    while (true) {
        const now = nowMilliseconds(io);
        const repeat_timeout = repeat.timeout(now);
        const animation = state.page == .games and state.library_view == .shelf and motion.active(now);
        var timeout: i32 = if (animation) (if (repeat_timeout < 0) @import("design.zig").motion.frame_ms else @min(@import("design.zig").motion.frame_ms, repeat_timeout)) else if (was_animating) 0 else repeat_timeout;
        if (save_deadline) |deadline| {
            const remaining: i32 = @intCast(@max(0, deadline - now));
            timeout = if (timeout < 0) remaining else @min(timeout, remaining);
        }
        const battery_wait: i32 = @intCast(@max(0, battery_deadline - now));
        timeout = if (timeout < 0) battery_wait else @min(timeout, battery_wait);
        if (wifi_client == null) {
            const reconnect_wait: i32 = @intCast(@max(0, wifi_reconnect_deadline - now));
            timeout = if (timeout < 0) reconnect_wait else @min(timeout, reconnect_wait);
        }
        if (bluetooth_client == null) {
            const reconnect_wait: i32 = @intCast(@max(0, bluetooth_reconnect_deadline - now));
            timeout = if (timeout < 0) reconnect_wait else @min(timeout, reconnect_wait);
        }
        const input_wait: i32 = @intCast(@max(0, input_rescan_deadline - now));
        timeout = if (timeout < 0) input_wait else @min(timeout, input_wait);
        if (state.page == .wifi or state.page == .wifi_fallback) {
            const captive_wait: i32 = @intCast(@max(0, captive_deadline - now));
            timeout = if (timeout < 0) captive_wait else @min(timeout, captive_wait);
        }
        for (gamepads.slots, 0..) |slot, index| {
            poll_fds[index].fd = slot.fd;
            poll_fds[index].revents = 0;
        }
        poll_fds[max_gamepads].fd = if (wifi_client) |client| client.fd else -1;
        poll_fds[max_gamepads].revents = 0;
        poll_fds[max_gamepads + 1].fd = if (bluetooth_client) |client| client.fd else -1;
        poll_fds[max_gamepads + 1].revents = 0;
        poll_fds[max_gamepads + 2].fd = input_monitor;
        poll_fds[max_gamepads + 2].revents = 0;
        _ = try std.posix.poll(&poll_fds, timeout);
        if (save_deadline) |deadline| if (nowMilliseconds(io) >= deadline) {
            saveLibraryPreferences(io, state);
            save_deadline = null;
        };
        var changed = animation or was_animating;
        if ((poll_fds[max_gamepads + 2].revents & std.posix.POLL.IN) != 0) {
            drainInputMonitor(input_monitor);
            changed = (try gamepads.rescan(io)) or changed;
        }
        if (nowMilliseconds(io) >= input_rescan_deadline) {
            changed = (try gamepads.rescan(io)) or changed;
            if (!gamepads.hasBuiltin()) return error.GamepadNotFound;
            input_rescan_deadline = nowMilliseconds(io) + 1000;
        }
        if ((state.page == .wifi or state.page == .wifi_fallback) and
            nowMilliseconds(io) >= captive_deadline)
        {
            changed = refreshCaptive(io, state) or changed;
            captive_deadline = nowMilliseconds(io) + 5000;
        }
        if (nowMilliseconds(io) >= battery_deadline) {
            const percent = batteryPercent(io);
            changed = changed or (state.page == .home and percent != state.battery_percent);
            state.battery_percent = percent;
            battery_deadline = nowMilliseconds(io) + 60000;
        }
        if (wifi_client == null and nowMilliseconds(io) >= wifi_reconnect_deadline) {
            wifi_client = wifi_ipc.Client.connect("/run/brick-wifi/control.sock") catch null;
            wifi_reconnect_deadline = nowMilliseconds(io) + 1000;
        }
        if (bluetooth_client == null and nowMilliseconds(io) >= bluetooth_reconnect_deadline) {
            bluetooth_client = bluetooth_ipc.Client.connect("/run/brick-bluetooth/control.sock") catch null;
            bluetooth_reconnect_deadline = nowMilliseconds(io) + 1000;
            bluetooth_request = 1;
        }
        if (wifi_client) |client| {
            if ((poll_fds[max_gamepads].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0) {
                client.close();
                wifi_client = null;
                wifi_reconnect_deadline = nowMilliseconds(io) + 1000;
                state.notice = "Wi-Fi service is restarting";
                changed = true;
            } else if ((poll_fds[max_gamepads].revents & std.posix.POLL.IN) != 0) {
                var packet: [wifi_ipc.max_packet]u8 = undefined;
                const event = client.receive(&packet) catch {
                    client.close();
                    wifi_client = null;
                    wifi_reconnect_deadline = nowMilliseconds(io) + 1000;
                    state.notice = "Wi-Fi service is restarting";
                    changed = true;
                    continue;
                };
                switch (event) {
                    .snapshot => |snapshot| {
                        changed = state.updateWifi(snapshot) or changed;
                        const changing = wifiChanging(state);
                        if (changing != network_changing) {
                            network_changing = changing;
                            var command = bluetooth.Command{ .generation = state.bluetooth.snapshot.generation, .request_id = 0, .kind = .network_activity, .value = changing };
                            _ = sendBluetooth(if (bluetooth_client) |*connected| connected else null, &bluetooth_request, &command);
                        }
                    },
                    .result => |result| switch (result.status) {
                        .accepted => {},
                        .stale => state.notice = "Wi-Fi changed. Try again.",
                        .rejected => state.notice = "Could not complete Wi-Fi action",
                    },
                }
            }
        }
        if (bluetooth_client) |client| {
            if ((poll_fds[max_gamepads + 1].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0) {
                client.close();
                bluetooth_client = null;
                bluetooth_reconnect_deadline = nowMilliseconds(io) + 1000;
                state.notice = "Bluetooth service is restarting";
                changed = true;
            } else if ((poll_fds[max_gamepads + 1].revents & std.posix.POLL.IN) != 0) {
                var packet: [bluetooth_ipc.max_packet]u8 = undefined;
                const event = client.receive(&packet) catch {
                    client.close();
                    bluetooth_client = null;
                    bluetooth_reconnect_deadline = nowMilliseconds(io) + 1000;
                    state.notice = "Bluetooth service is restarting";
                    changed = true;
                    continue;
                };
                switch (event) {
                    .snapshot => |snapshot| changed = state.updateBluetooth(snapshot) or changed,
                    .result => |result| switch (result.status) {
                        .accepted => {},
                        .stale => state.notice = "Bluetooth changed. Try again.",
                        .rejected => state.notice = "Could not complete Bluetooth action",
                    },
                }
            }
        }
        was_animating = animation;
        {
            if (repeat.due(nowMilliseconds(io))) |action| if (repeatAllowed(state, action)) {
                const previous = state.selected;
                const result = try applySessionAction(io, state, &framebuffer, if (wifi_client) |*client| client else null, if (bluetooth_client) |*client| client else null, &bluetooth_request, action);
                if (wifi_only and state.page != .wifi and state.page != .wifi_fallback) return null;
                if (state.page == .games and state.library_view == .shelf and previous != state.selected)
                    motion.retarget(@as(i32, @intCast(state.selected)) - @as(i32, @intCast(previous)), nowMilliseconds(io));
                if (result.launch) |index| return index;
                changed = changed or result.changed;
                if (result.changed) save_deadline = nowMilliseconds(io) + 1000;
            };
        }
        for (&gamepads.slots, 0..) |*slot, slot_index| {
            if (slot.fd < 0) continue;
            if ((poll_fds[slot_index].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0) {
                closeFd(io, slot.fd, true);
                slot.* = .{};
                repeat.reset();
                input_rescan_deadline = nowMilliseconds(io);
                continue;
            }
            while ((poll_fds[slot_index].revents & std.posix.POLL.IN) != 0) {
                const bytes_read = std.posix.read(slot.fd, &buffer) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => return err,
                };
                if (bytes_read == 0) break;
                if (bytes_read % @sizeOf(InputEvent) != 0) return error.InvalidInputEvent;
                for (std.mem.bytesAsSlice(InputEvent, buffer[0..bytes_read])) |event| {
                    observeRepeat(&repeat, event, nowMilliseconds(io));
                    if (actionForEvent(event, slot.builtin, &slot.dropped)) |action| {
                        const previous = state.selected;
                        const result = try applySessionAction(io, state, &framebuffer, if (wifi_client) |*client| client else null, if (bluetooth_client) |*client| client else null, &bluetooth_request, action);
                        if (wifi_only and state.page != .wifi and state.page != .wifi_fallback) return null;
                        if (state.page == .games and state.library_view == .shelf and previous != state.selected)
                            motion.retarget(@as(i32, @intCast(state.selected)) - @as(i32, @intCast(previous)), nowMilliseconds(io));
                        if (result.launch) |index| return index;
                        changed = changed or result.changed;
                        if (result.changed) save_deadline = nowMilliseconds(io) + 1000;
                    }
                }
                if (bytes_read < buffer.len) break;
            }
        }
        if (changed) {
            tree = state.treeWithShelfOffset(motion.offset(nowMilliseconds(io)));
            try framebuffer.show(&tree);
        }
    }
}

fn runOverlay(io: std.Io, state: *overlay.Model) !overlay.Command {
    var console = try Console.open(io);
    defer console.close();
    var framebuffer = try Framebuffer.open(io);
    defer framebuffer.close();

    var tree = state.tree();
    try framebuffer.show(&tree);
    var gamepads = Gamepads{};
    defer gamepads.close(io);
    _ = try gamepads.rescan(io);
    if (!gamepads.hasBuiltin()) return error.GamepadNotFound;
    const input_monitor = try openInputMonitor();
    defer closeFd(io, input_monitor, true);
    var rescan_deadline = nowMilliseconds(io) + 1000;
    var poll_fds: [max_gamepads + 1]std.posix.pollfd = @splat(.{ .fd = -1, .events = std.posix.POLL.IN, .revents = 0 });
    var repeat: input_repeat.Controller = .{};
    var buffer: [32 * @sizeOf(InputEvent)]u8 align(@alignOf(InputEvent)) = undefined;

    while (true) {
        for (gamepads.slots, 0..) |slot, index| {
            poll_fds[index].fd = slot.fd;
            poll_fds[index].revents = 0;
        }
        poll_fds[max_gamepads].fd = input_monitor;
        poll_fds[max_gamepads].revents = 0;
        const now = nowMilliseconds(io);
        const repeat_wait = repeat.timeout(now);
        const scan_wait: i32 = @intCast(@max(0, rescan_deadline - now));
        const timeout = if (repeat_wait < 0) scan_wait else @min(repeat_wait, scan_wait);
        const ready = try std.posix.poll(&poll_fds, timeout);
        var changed = false;
        if ((poll_fds[max_gamepads].revents & std.posix.POLL.IN) != 0) {
            drainInputMonitor(input_monitor);
            _ = try gamepads.rescan(io);
        }
        if (nowMilliseconds(io) >= rescan_deadline) {
            _ = try gamepads.rescan(io);
            if (!gamepads.hasBuiltin()) return error.GamepadNotFound;
            rescan_deadline = nowMilliseconds(io) + 1000;
        }
        if (ready == 0) {
            if (repeat.due(nowMilliseconds(io))) |action| {
                if (action == .up or action == .down)
                    changed = state.apply(action) or changed;
            }
        }
        for (&gamepads.slots, 0..) |*slot, slot_index| {
            if (slot.fd < 0) continue;
            if ((poll_fds[slot_index].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0) {
                closeFd(io, slot.fd, true);
                slot.* = .{};
                repeat.reset();
                rescan_deadline = nowMilliseconds(io);
                continue;
            }
            while ((poll_fds[slot_index].revents & std.posix.POLL.IN) != 0) {
                const bytes_read = std.posix.read(slot.fd, &buffer) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => return err,
                };
                if (bytes_read == 0) break;
                if (bytes_read % @sizeOf(InputEvent) != 0) return error.InvalidInputEvent;
                for (std.mem.bytesAsSlice(InputEvent, buffer[0..bytes_read])) |event| {
                    observeRepeat(&repeat, event, nowMilliseconds(io));
                    if (actionForEvent(event, slot.builtin, &slot.dropped)) |action| {
                        if (state.apply(action)) changed = true;
                        if (state.takeCommand()) |command| {
                            if (command == .save_state or command == .load_state) {
                                var status = ui.message(state.appearance.colors(), if (command == .save_state) "Save state" else "Load state", if (command == .save_state) "Saving state…" else "Loading state…", "");
                                try framebuffer.show(&status);
                            }
                            return command;
                        }
                    }
                }
                if (bytes_read < buffer.len) break;
            }
        }
        if (changed) {
            tree = state.tree();
            try framebuffer.show(&tree);
        }
    }
}

fn refreshWifi(state: *model.Model) void {
    const client = wifi_ipc.Client.connect("/run/brick-wifi/control.sock") catch return;
    defer client.close();
    var descriptor = [_]std.posix.pollfd{.{ .fd = client.fd, .events = std.posix.POLL.IN, .revents = 0 }};
    if ((std.posix.poll(&descriptor, 250) catch return) != 1 or
        (descriptor[0].revents & std.posix.POLL.IN) == 0) return;
    var packet: [wifi_ipc.max_packet]u8 = undefined;
    const event = client.receive(&packet) catch return;
    switch (event) {
        .snapshot => |snapshot| _ = state.updateWifi(snapshot),
        .result => {},
    }
}

pub fn run(io: std.Io) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const initial_settings = settings.load(io);
    {
        var console = try Console.open(io);
        defer console.close();
        var framebuffer = try Framebuffer.open(io);
        defer framebuffer.close();
        var splash = ui.splash(initial_settings.appearance.colors());
        try framebuffer.show(&splash);
    }
    const library = try catalog.discover(io, arena.allocator(), "/data");
    var state = model.Model{ .games = library, .settings = initial_settings };
    if (std.Io.Dir.cwd().openDir(io, "/data/settings", .{})) |dir| {
        defer dir.close(io);
        @import("library_preferences.zig").load(io, dir, &state);
    } else |_| {}
    if (state.last_played) |index| state.resumable = retroarch.availableStates(io, &state.games[index])[3];
    while (true) {
        const game_index = (try runSession(io, &state, false)) orelse continue;
        const game = &state.games[game_index];
        var game_overlay = overlay.Model{
            .appearance = state.settings.appearance,
            .title = game.title,
            .system = game.system,
            .performance_profile = @backingInt(state.settings.performance),
        };
        game_session: while (true) {
            const term = retroarch.launch(io, game, state.games) catch |err| {
                state.launchFailed(retroarch.Failure.fromError(err));
                break :game_session;
            };
            switch (term) {
                .exited => |status| if (status != 0) {
                    state.launchFailed(.emulator);
                    break :game_session;
                },
                else => {
                    state.launchFailed(.emulator);
                    break :game_session;
                },
            }
            state.last_played = game_index;
            state.resumable = retroarch.availableStates(io, game)[3];
            saveLibraryPreferences(io, &state);
            if (retroarch.takeAudioLoss())
                game_overlay.notice = "Bluetooth audio disconnected. Reconnect it, then relaunch the game.";
            while (true) {
                refreshWifi(&state);
                game_overlay.network_status = state.wifi.wifi_state.snapshot.settingsSummary();
                game_overlay.available = retroarch.availableStates(io, game);
                switch (try runOverlay(io, &game_overlay)) {
                    .resume_game => {
                        game_overlay.layer = .pause;
                        game_overlay.selected = 0;
                        continue :game_session;
                    },
                    .exit_game => {
                        if (!game_overlay.available[3]) {
                            game_overlay.layer = .failure;
                            game_overlay.failed_command = .exit_game;
                            game_overlay.notice = "No automatic state was saved. Return to the game and try again.";
                            continue;
                        }
                        break :game_session;
                    },
                    .save_state => {
                        retroarch.saveState(io, game, state.games, game_overlay.save_slot) catch |err| {
                            game_overlay.saved = false;
                            game_overlay.layer = .failure;
                            game_overlay.confirmation = 0;
                            game_overlay.failed_command = .save_state;
                            game_overlay.notice = "Could not write the saved state. Check free space on the SD card.";
                            std.log.err("Failed to save state: {s}", .{@errorName(err)});
                            continue;
                        };
                        game_overlay.layer = .pause;
                        game_overlay.selected = 1;
                        game_overlay.saved = true;
                        game_overlay.notice = "State saved";
                    },
                    .load_state => {
                        retroarch.loadState(io, game, state.games, game_overlay.state_slot) catch |err| {
                            game_overlay.layer = .states;
                            game_overlay.notice = "Could not load that saved state";
                            std.log.err("Failed to load state: {s}", .{@errorName(err)});
                            continue;
                        };
                        game_overlay.notice = "";
                        game_overlay.layer = .pause;
                        game_overlay.selected = 0;
                        continue :game_session;
                    },
                    .apply_performance => {
                        state.settings.performance = @fromBackingInt(@intCast(game_overlay.performance_profile));
                        settings.apply(io, state.settings, .performance) catch |err| {
                            state.settings = settings.load(io);
                            game_overlay.performance_profile = @backingInt(state.settings.performance);
                            game_overlay.notice = "Could not apply performance profile";
                            std.log.err("Failed to apply performance profile: {s}", .{@errorName(err)});
                        };
                    },
                    .network_settings => {
                        state.page = .wifi;
                        state.selected = 0;
                        state.wifi.page = .list;
                        _ = try runSession(io, &state, true);
                        state.page = .home;
                        state.selected = 0;
                        continue;
                    },
                }
            }
        }
    }
}

pub fn probe(io: std.Io) !void {
    var console = try Console.open(io);
    defer console.close();
    var framebuffer = try Framebuffer.open(io);
    defer framebuffer.close();
    var gamepads = Gamepads{};
    defer gamepads.close(io);
    _ = try gamepads.rescan(io);
    if (!gamepads.hasBuiltin()) return error.GamepadNotFound;
    var state = model.Model{};
    var tree = state.tree();
    try framebuffer.show(&tree);
}

test "navigation presses and dropped streams resynchronise" {
    const testing = std.testing;
    var dropped = false;
    try testing.expectEqual(model.Action.down, actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_dpad_down, .value = 1 }, true, &dropped).?);
    try testing.expectEqual(model.Action.left, actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_dpad_left, .value = 1 }, true, &dropped).?);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_dpad_down, .value = 2 }, true, &dropped) == null);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_east, .value = 2 }, true, &dropped) == null);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_syn, .code = syn_dropped, .value = 0 }, true, &dropped) == null);
    try testing.expect(dropped);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_east, .value = 1 }, true, &dropped) == null);
    _ = actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_syn, .code = 0, .value = 0 }, true, &dropped);
    try testing.expect(!dropped);
}

test "input capability bitmaps and external gamepad conventions" {
    try std.testing.expect(capabilityHas("1 0", 4));
    try std.testing.expect(!capabilityHas("1 0", 0));
    var dropped = false;
    try std.testing.expectEqual(model.Action.select, actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_south, .value = 1 }, false, &dropped).?);
    try std.testing.expectEqual(model.Action.back, actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_east, .value = 1 }, false, &dropped).?);
    try std.testing.expectEqual(model.Action.left, actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_abs, .code = abs_hat0_x, .value = -1 }, false, &dropped).?);
}

fn performPower(io: std.Io, command: model.Power) !void {
    const argv: []const []const u8 = switch (command) {
        .screen_off => &.{ "/usr/sbin/brick-brightness", "--off" },
        .suspend_device => &.{ "/usr/sbin/brick-suspend", "--disconnect-bluetooth" },
        .shutdown => &.{"/sbin/poweroff"},
    };
    var child = try std.process.spawn(io, .{ .argv = argv });
    switch (try child.wait(io)) {
        .exited => |status| if (status != 0) return error.PowerActionFailed,
        else => return error.PowerActionFailed,
    }
}

fn batteryPercent(io: std.Io) ?u8 {
    var buffer: [16]u8 = undefined;
    const bytes = std.Io.Dir.cwd().readFile(io, "/sys/class/power_supply/axp2202-battery/capacity", &buffer) catch return null;
    const value = std.fmt.parseInt(u8, std.mem.trim(u8, bytes, " \r\n"), 10) catch return null;
    return if (value <= 100) value else null;
}
