// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const catalog = @import("catalog.zig");
const input_repeat = @import("input_repeat.zig");
const model = @import("model.zig");
const overlay = @import("overlay.zig");
const render = @import("render.zig");
const retroarch = @import("retroarch.zig");
const ui = @import("ui.zig");
const settings = @import("settings.zig");

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
const syn_report: u16 = 0x00;
const syn_dropped: u16 = 0x03;
const btn_south: u16 = 0x130;
const btn_east: u16 = 0x131;
const btn_mode: u16 = 0x13c;
const btn_view: u16 = 0x2c0;
const btn_dpad_up: u16 = 0x220;
const btn_dpad_down: u16 = 0x221;
const btn_dpad_left: u16 = 0x222;
const btn_dpad_right: u16 = 0x223;

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
    if (event.event_type == ev_syn and event.code == syn_dropped) {
        dropped.* = true;
        return null;
    }
    if (dropped.*) {
        if (event.event_type == ev_syn and event.code == syn_report) dropped.* = false;
        return null;
    }
    if (event.event_type != ev_key or event.value != 1) return null;
    return switch (event.code) {
        btn_dpad_up => .up,
        btn_dpad_down => .down,
        btn_dpad_left => .left,
        btn_dpad_right => .right,
        btn_east => .select,
        btn_south => .back,
        btn_mode => .menu,
        btn_view => .view,
        else => null,
    };
}

fn directionForCode(code: u16) ?model.Action {
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
    if (event.event_type != ev_key) return;
    const action = directionForCode(event.code) orelse return;
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

fn applySessionAction(io: std.Io, state: *model.Model, framebuffer: *Framebuffer, tree: *ui.Tree, action: model.Action, animate: bool) !SessionAction {
    const previous_selected = state.selected;
    if (!state.apply(action)) return .{};
    if (state.takeSetting()) |setting|
        settings.apply(io, state.settings, setting) catch {
            state.settings = settings.load(io);
        };
    if (state.takeLaunch()) |index| return .{ .launch = index };
    if (animate and state.page == .games and state.library_view == .shelf and previous_selected != state.selected) {
        const initial: i16 = if (state.selected > previous_selected) 1000 else -1000;
        var frame: i16 = 4;
        while (frame > 0) : (frame -= 1) {
            tree.* = state.treeWithShelfOffset(@divTrunc(initial * frame, 5));
            try framebuffer.show(tree);
        }
    }
    return .{ .changed = true };
}

fn runSession(io: std.Io, state: *model.Model) !?usize {
    // Stop fbcon from drawing its text cursor over the product surface.
    var console = try Console.open(io);
    defer console.close();
    var framebuffer = try Framebuffer.open(io);
    defer framebuffer.close();

    var splash_tree = ui.splash();
    try framebuffer.show(&splash_tree);
    // One short, deliberate beat makes boot progress visible without adding a
    // quarter-second gate before the first interactive frame.
    try std.Io.sleep(io, .fromMilliseconds(120), .awake);

    var tree = state.tree();
    try framebuffer.show(&tree);

    const input_fd = try discoverGamepad(io);
    defer closeFd(io, input_fd, true);
    var poll_fds = [_]std.posix.pollfd{.{ .fd = input_fd, .events = std.posix.POLL.IN, .revents = 0 }};
    var dropped = false;
    var repeat: input_repeat.Controller = .{};
    var buffer: [32 * @sizeOf(InputEvent)]u8 align(@alignOf(InputEvent)) = undefined;

    while (true) {
        const ready = try std.posix.poll(&poll_fds, repeat.timeout(nowMilliseconds(io)));
        if ((poll_fds[0].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0)
            return error.GamepadDisconnected;
        var changed = false;
        if (ready == 0) {
            if (repeat.due(nowMilliseconds(io))) |action| if (repeatAllowed(state, action)) {
                const result = try applySessionAction(io, state, &framebuffer, &tree, action, false);
                if (result.launch) |index| return index;
                changed = result.changed;
            };
        }
        while ((poll_fds[0].revents & std.posix.POLL.IN) != 0) {
            const bytes_read = std.posix.read(input_fd, &buffer) catch |err| switch (err) {
                error.WouldBlock => break,
                else => return err,
            };
            if (bytes_read == 0) return error.GamepadDisconnected;
            if (bytes_read % @sizeOf(InputEvent) != 0) return error.InvalidInputEvent;
            const events = std.mem.bytesAsSlice(InputEvent, buffer[0..bytes_read]);
            for (events) |event| {
                observeRepeat(&repeat, event, nowMilliseconds(io));
                if (actionForEvent(event, &dropped)) |action| {
                    const result = try applySessionAction(io, state, &framebuffer, &tree, action, true);
                    if (result.launch) |index| return index;
                    changed = changed or result.changed;
                }
            }
            if (bytes_read < buffer.len) break;
        }
        if (changed) {
            tree = state.tree();
            try framebuffer.show(&tree);
        }
    }
}

fn runOverlay(io: std.Io, state: *overlay.Model) !overlay.Command {
    var console = try Console.open(io);
    defer console.close();
    var framebuffer = try Framebuffer.open(io);
    defer framebuffer.close();
    try framebuffer.captureBackground();

    var tree = state.tree();
    try framebuffer.show(&tree);
    const input_fd = try discoverGamepad(io);
    defer closeFd(io, input_fd, true);
    var poll_fds = [_]std.posix.pollfd{.{ .fd = input_fd, .events = std.posix.POLL.IN, .revents = 0 }};
    var dropped = false;
    var repeat: input_repeat.Controller = .{};
    var buffer: [32 * @sizeOf(InputEvent)]u8 align(@alignOf(InputEvent)) = undefined;

    while (true) {
        const ready = try std.posix.poll(&poll_fds, repeat.timeout(nowMilliseconds(io)));
        if ((poll_fds[0].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0)
            return error.GamepadDisconnected;
        var changed = false;
        if (ready == 0) {
            if (repeat.due(nowMilliseconds(io))) |action| {
                if (action == .up or action == .down)
                    changed = state.apply(action) or changed;
            }
        }
        while ((poll_fds[0].revents & std.posix.POLL.IN) != 0) {
            const bytes_read = std.posix.read(input_fd, &buffer) catch |err| switch (err) {
                error.WouldBlock => break,
                else => return err,
            };
            if (bytes_read == 0) return error.GamepadDisconnected;
            if (bytes_read % @sizeOf(InputEvent) != 0) return error.InvalidInputEvent;
            for (std.mem.bytesAsSlice(InputEvent, buffer[0..bytes_read])) |event| {
                observeRepeat(&repeat, event, nowMilliseconds(io));
                if (actionForEvent(event, &dropped)) |action| {
                    if (state.apply(action)) changed = true;
                    if (state.takeCommand()) |command| return command;
                }
            }
            if (bytes_read < buffer.len) break;
        }
        if (changed) {
            tree = state.tree();
            try framebuffer.show(&tree);
        }
    }
}

pub fn run(io: std.Io) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const library = try catalog.discover(io, arena.allocator(), "/data");
    var state = model.Model{ .games = library, .settings = settings.load(io) };
    while (true) {
        const game_index = (try runSession(io, &state)) orelse continue;
        const game = &state.games[game_index];
        var game_overlay = overlay.Model{
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
            while (true) {
                switch (try runOverlay(io, &game_overlay)) {
                    .resume_game => continue :game_session,
                    .exit_game => break :game_session,
                    .save_state => {
                        retroarch.saveState(io, game, state.games, game_overlay.save_slot) catch |err| {
                            game_overlay.saved = false;
                            game_overlay.notice = "Save failed";
                            std.log.err("Failed to save state: {s}", .{@errorName(err)});
                        };
                    },
                    .load_state => {
                        retroarch.loadState(io, game, state.games, game_overlay.state_slot) catch |err| {
                            game_overlay.notice = "No save in that slot";
                            std.log.err("Failed to load state: {s}", .{@errorName(err)});
                            continue;
                        };
                        game_overlay.notice = "";
                        continue :game_session;
                    },
                    .apply_performance => {
                        state.settings.performance = @fromBackingInt(@intCast(game_overlay.performance_profile));
                        settings.apply(io, state.settings, .performance) catch |err|
                            std.log.err("Failed to apply performance profile: {s}", .{@errorName(err)});
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
    const input_fd = try discoverGamepad(io);
    defer closeFd(io, input_fd, true);
    var state = model.Model{};
    var tree = state.tree();
    try framebuffer.show(&tree);
}

test "navigation presses and dropped streams resynchronise" {
    const testing = std.testing;
    var dropped = false;
    try testing.expectEqual(model.Action.down, actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_dpad_down, .value = 1 }, &dropped).?);
    try testing.expectEqual(model.Action.left, actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_dpad_left, .value = 1 }, &dropped).?);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_dpad_down, .value = 2 }, &dropped) == null);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_east, .value = 2 }, &dropped) == null);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_syn, .code = syn_dropped, .value = 0 }, &dropped) == null);
    try testing.expect(dropped);
    try testing.expect(actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_east, .value = 1 }, &dropped) == null);
    _ = actionForEvent(.{ .seconds = 0, .microseconds = 0, .event_type = ev_syn, .code = 0, .value = 0 }, &dropped);
    try testing.expect(!dropped);
}
