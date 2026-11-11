// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const activity_motion = @import("activity_motion.zig");
const bluetooth = @import("bluetooth.zig");
const catalog = @import("catalog.zig");
const captive = @import("captive.zig");
const design = @import("design.zig");
const display_scheduler = @import("display_scheduler.zig");
const input_repeat = @import("input_repeat.zig");
const interaction = @import("interaction.zig");
const interaction_motion = @import("motion.zig");
const model = @import("model.zig");
const navigation_motion = @import("navigation_motion.zig");
const overlay = @import("overlay.zig");
const retroarch = @import("retroarch.zig");
const scene_motion = @import("scene_motion.zig");
const ui = @import("ui.zig");
const ui_components = @import("ui_components.zig");
const settings = @import("settings.zig");
const bluetooth_ipc = @import("bluetooth_ipc.zig");
const wifi_ipc = @import("wifi_ipc.zig");

const tty_path = "/dev/tty0";
const kd_set_mode: u32 = 0x4b3a;
const kd_graphics: usize = 1;
var profile_input = false;
pub const Profile = enum { settings, shelf, overlay };

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

fn readAttribute(io: std.Io, path: []const u8, buffer: []u8) ![]const u8 {
    const bytes = try std.Io.Dir.cwd().readFile(io, path, buffer);
    return std.mem.trim(u8, bytes, " \t\r\n");
}

fn closeFd(io: std.Io, fd: std.posix.fd_t, nonblocking: bool) void {
    (std.Io.File{ .handle = fd, .flags = .{ .nonblocking = nonblocking } }).close(io);
}

const Display = display_scheduler.Scheduler;
const brightness_meter_id = interaction.Id.scoped(.brightness_meter, 0);

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
        // Do not switch through KD_TEXT between the splash, menu, emulator,
        // and overlay. fbcon applies that transition asynchronously and can
        // reset fb_info.var.yoffset after the next owner has acquired fb0.
        // Every graphical owner asserts its own mode when it opens the tty.
        closeFd(self.io, self.fd, false);
    }
};

const max_gamepads = 8;
const input_directory = "/dev/input";
const InputPaths = struct { devices: []const u8 = input_directory, sysfs: []const u8 = "/sys/class/input" };
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
        return self.rescanAt(io, .{});
    }

    fn rescanAt(self: *Gamepads, io: std.Io, paths: InputPaths) !bool {
        const started = if (profile_input) std.Io.Timestamp.now(io, .awake).toMicroseconds() else 0;
        defer if (profile_input) std.log.info("UI input scan: start={d}us work={d}us", .{ started, std.Io.Timestamp.now(io, .awake).toMicroseconds() - started });
        var present: [64]bool = @splat(false);
        var changed = false;
        for (0..64) |raw_index| {
            var path_buffer: [512]u8 = undefined;
            const name_path = try std.fmt.bufPrint(&path_buffer, "{s}/event{d}/device/name", .{ paths.sysfs, raw_index });
            var name_buffer: [128]u8 = undefined;
            const name = readAttribute(io, name_path, &name_buffer) catch continue;
            var capability_buffer: [1024]u8 = undefined;
            const capability_path = try std.fmt.bufPrint(&path_buffer, "{s}/event{d}/device/capabilities/key", .{ paths.sysfs, raw_index });
            const capabilities = readAttribute(io, capability_path, &capability_buffer) catch continue;
            const builtin = std.mem.eql(u8, name, "TrimUI Brick Gamepad");
            if (!builtin and !capabilityHas(capabilities, btn_south)) continue;
            present[raw_index] = true;
            const index: u8 = @intCast(raw_index);
            if (self.hasIndex(index)) continue;
            for (&self.slots) |*slot| if (slot.fd < 0) {
                const event_path = try std.fmt.bufPrint(&path_buffer, "{s}/event{d}", .{ paths.devices, raw_index });
                const fd = std.posix.openat(std.posix.AT.FDCWD, event_path, .{
                    .ACCMODE = .RDONLY,
                    .CLOEXEC = true,
                    .NONBLOCK = true,
                }, 0) catch break;
                if (profile_input) {
                    const monotonic: c_int = 1;
                    if (std.posix.errno(std.os.linux.ioctl(fd, 0x400445a0, @intFromPtr(&monotonic))) != .SUCCESS) {
                        closeFd(io, fd, true);
                        return error.InputClock;
                    }
                }
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

// Watch before enumerating so hotplug during startup remains queued.
fn openInputMonitor(path: [*:0]const u8) !std.posix.fd_t {
    const raw = std.os.linux.inotify_init1(std.os.linux.IN.CLOEXEC | std.os.linux.IN.NONBLOCK);
    if (std.posix.errno(raw) != .SUCCESS) return error.InputMonitorUnavailable;
    const fd: std.posix.fd_t = @intCast(raw);
    errdefer _ = std.os.linux.close(fd);
    const watch = std.os.linux.inotify_add_watch(fd, path, std.os.linux.IN.CREATE | std.os.linux.IN.DELETE | std.os.linux.IN.MOVED_TO | std.os.linux.IN.MOVED_FROM | std.os.linux.IN.ATTRIB | std.os.linux.IN.DELETE_SELF | std.os.linux.IN.MOVE_SELF);
    if (std.posix.errno(watch) != .SUCCESS) return error.InputMonitorUnavailable;
    return fd;
}

const InputMonitorEvent = extern struct { watch: i32, mask: u32, cookie: u32, name_len: u32 };

fn checkInputMonitorEvents(bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        if (bytes.len - offset < @sizeOf(InputMonitorEvent)) return error.InvalidInputMonitorEvent;
        const event = std.mem.bytesToValue(InputMonitorEvent, bytes[offset..][0..@sizeOf(InputMonitorEvent)]);
        offset += @sizeOf(InputMonitorEvent);
        if (event.name_len > bytes.len - offset) return error.InvalidInputMonitorEvent;
        offset += event.name_len;
        if (event.mask & (std.os.linux.IN.IGNORED | std.os.linux.IN.UNMOUNT | std.os.linux.IN.DELETE_SELF | std.os.linux.IN.MOVE_SELF) != 0)
            return error.InputMonitorUnavailable;
    }
}

fn drainInputMonitor(fd: std.posix.fd_t) !void {
    var events: [1024]u8 = undefined;
    while (true) {
        const result = std.posix.read(fd, &events) catch |err| switch (err) {
            error.WouldBlock => return,
            else => return err,
        };
        if (result == 0) return error.InputMonitorUnavailable;
        try checkInputMonitorEvents(events[0..result]);
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

fn selectButtonEvent(event: InputEvent, builtin: bool) ?bool {
    if (event.event_type != ev_key or (event.value != 0 and event.value != 1)) return null;
    const action: ?model.Action = switch (event.code) {
        btn_east => if (builtin) .select else .back,
        btn_south => if (builtin) .back else .select,
        else => null,
    };
    if (action != .select) return null;
    return event.value == 1;
}

const PressResult = enum { none, pressed, activated, cancelled };
const PressTracker = struct {
    id: ?interaction.Id = null,
    armed: bool = false,

    noinline fn observe(self: *PressTracker, event: InputEvent, builtin: bool, dropped: bool, tree: *const ui.Tree) PressResult {
        if (event.event_type == ev_syn and event.code == syn_dropped) {
            self.clear();
            return .cancelled;
        }
        if (dropped) return .none;
        const down = selectButtonEvent(event, builtin) orelse return .none;
        if (down) {
            self.armed = true;
            self.id = tree.focusedId();
            return .pressed;
        }
        if (!self.armed) return .none;
        self.clear();
        return .activated;
    }

    fn clear(self: *PressTracker) void {
        self.* = .{};
    }

    noinline fn decorate(self: PressTracker, tree: *ui.Tree) void {
        if (self.id) |id| _ = tree.setInteraction(id, .pressed);
    }
};

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
        (state.page == .games and state.library_view == .browse and (action == .left or action == .right));
}

fn directional(action: model.Action) bool {
    return action == .up or action == .down or action == .left or action == .right;
}

const SessionAction = struct { changed: bool = false, launch: ?usize = null };

fn beginNavigation(
    state: *model.Model,
    now_ms: i64,
    presentation: *scene_motion.Controller,
) ui.Tree {
    var destination = state.tree();
    presentation.cutTo(&destination, now_ms, state.settings.reduced_motion, brightness_meter_id);
    return destination;
}

fn beginOverlayNavigation(
    state: *overlay.Model,
    source: *const ui.Tree,
    from_layer: overlay.Layer,
    action: model.Action,
    now_ms: i64,
    presentation: *scene_motion.Controller,
) ui.Tree {
    var destination = state.tree();
    presentation.beginNavigation(source, &destination, if (overlay.returnsToParent(action, from_layer, state.layer)) .back else .forward, now_ms, state.reduced_motion, null);
    return destination;
}

/// Present the launch destination before synchronous content/core preparation
/// can block the shell. The selected control remains the transition anchor and
/// the shared activity cadence starts during the reveal.
fn presentLaunch(io: std.Io, display: *Display, source: *const ui.Tree, state: *const model.Model, index: usize) !void {
    if (index >= state.games.len) return error.InvalidGameIndex;
    var destination = ui.gameDetail(state.settings.appearance.colors(), state.games[index], null);
    const started = nowMilliseconds(io);
    var activity: activity_motion.Controller = .{};
    activity.update(&destination, started, state.settings.reduced_motion);
    activity.decorate(&destination, started);
    var transition: navigation_motion.Controller = .{};
    transition.begin(source, &destination, .forward, started, state.settings.reduced_motion);
    var now = started;
    while (transition.active(now)) {
        const next_frame = now + design.motion_tokens.enter.frame_ms;
        activity.decorate(&transition.to, now);
        try display.submitTransition(&transition, now);
        const presented = nowMilliseconds(io);
        if (presented < next_frame)
            try std.Io.sleep(io, .fromMilliseconds(next_frame - presented), .awake);
        now = nowMilliseconds(io);
    }
    activity.decorate(&destination, now);
    try display.show(&destination);
}

fn saveLibraryPreferences(io: std.Io, state: *const model.Model) void {
    if (profile_input) return;
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

fn applySessionAction(io: std.Io, state: *model.Model, display: *Display, wifi_client: ?*wifi_ipc.Client, bluetooth_client: ?*bluetooth_ipc.Client, bluetooth_request: *u32, action: model.Action) !SessionAction {
    if (!state.apply(action)) return .{};
    state.feedback = .{};
    if (state.takeSetting()) |setting| {
        if (settings.apply(io, state.settings, setting)) |_| {
            state.feedback = .{ .kind = .success, .message = switch (setting) {
                .brightness => "Brightness saved",
                .performance => "Performance mode saved",
                .display_timeout => "Screen-off timeout saved",
                .suspend_timeout => "Suspend timeout saved",
                .appearance => "Appearance changed",
                .reduced_motion => if (state.settings.reduced_motion) "Reduced motion on" else "Reduced motion off",
            } };
        } else |_| {
            state.settings = settings.load(io);
            state.feedback = .{ .kind = .failure, .message = "Could not apply setting" };
        }
    }
    if (state.takeWifiRequest()) |pending| {
        var request = pending;
        state.feedback = .{ .kind = .progress, .message = switch (request.command.kind) {
            .set_enabled => if (request.command.value) "Turning Wi-Fi on" else "Turning Wi-Fi off",
            .scan => "Refreshing networks",
            .connect => "Connecting to Wi-Fi",
            .cancel => "Cancelling Wi-Fi action",
            .disconnect => "Disconnecting from Wi-Fi",
            .forget => "Forgetting network",
            .set_auto_connect, .set_private_address => "Saving network setting",
            .open_captive => "Opening Wi-Fi sign in",
            .recheck => "Checking internet access",
        } };
        if (wifi_client) |client| client.send(&request) catch {
            state.feedback = .{ .kind = .failure, .message = "Wi-Fi is unavailable" };
        } else {
            request.wipe();
            state.feedback = .{ .kind = .failure, .message = "Wi-Fi is unavailable" };
        }
    }
    if (state.takeBluetoothCommand()) |pending| {
        var command = pending;
        state.feedback = .{ .kind = .progress, .message = switch (command.kind) {
            .set_radio => if (command.value) "Turning Bluetooth on" else "Turning Bluetooth off",
            .start_search => "Looking for devices",
            .cancel => "Cancelling Bluetooth action",
            .pair => "Pairing device",
            .connect => "Connecting device",
            .disconnect => "Disconnecting device",
            .forget => "Forgetting device",
            .select_audio => "Preparing game audio",
            .confirm_pairing, .submit_passkey => "Confirming pairing",
            .network_activity => "Coordinating radios",
        } };
        if (!sendBluetooth(bluetooth_client, bluetooth_request, &command))
            state.feedback = .{ .kind = .failure, .message = "Bluetooth is unavailable" };
    }
    if (state.pending_power) |command| {
        state.pending_power = null;
        saveLibraryPreferences(io, state);
        var status = ui.message(state.settings.appearance.colors(), "Power", switch (command) {
            .screen_off => "",
            .suspend_device => "Going to sleep…",
            .shutdown => "Shutting down…",
        }, "");
        try display.show(&status);
        performPower(io, command) catch {
            state.feedback = .{ .kind = .failure, .message = if (command == .suspend_device) "Unable to sleep. The device is still awake." else "Could not complete power action" };
        };
        state.page = .foyer;
        state.selected = 0;
    }
    if (state.takeLaunch()) |index| {
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

fn markReady(io: std.Io) !void {
    const ready = try std.Io.Dir.cwd().createFile(io, "/run/brick-shell.ready", .{});
    ready.close(io);
}

fn runSession(io: std.Io, state: *model.Model, wifi_only: bool) !?usize {
    // Stop fbcon from drawing its text cursor over the product surface.
    var console = try Console.open(io);
    defer console.close();
    var display = try Display.open(io, profile_input);
    defer display.close();

    state.battery_percent = batteryPercent(io);
    var battery_deadline = nowMilliseconds(io) + 60000;
    // SAFETY: reset initializes every field before presentation is observed.
    var presentation: scene_motion.Controller = undefined;
    presentation.reset();
    var tree = state.tree();
    presentation.decorate(&tree, nowMilliseconds(io), state.settings.reduced_motion, brightness_meter_id);
    try display.show(&tree);

    var wifi_client: ?wifi_ipc.Client = wifi_ipc.Client.connect("/run/brick-wifi/control.sock") catch null;
    defer if (wifi_client) |client| client.close();
    var wifi_reconnect_deadline = nowMilliseconds(io) + 1000;
    var bluetooth_client: ?bluetooth_ipc.Client = bluetooth_ipc.Client.connect("/run/brick-bluetooth/control.sock") catch null;
    defer if (bluetooth_client) |client| client.close();
    var bluetooth_reconnect_deadline = nowMilliseconds(io) + 1000;
    var bluetooth_request: u32 = 1;
    var network_changing = false;
    var captive_deadline = nowMilliseconds(io);

    const input_monitor = try openInputMonitor(input_directory);
    defer closeFd(io, input_monitor, true);
    var gamepads = Gamepads{};
    defer gamepads.close(io);
    _ = try gamepads.rescan(io);
    if (!gamepads.hasBuiltin()) return error.GamepadNotFound;
    try markReady(io);
    var poll_fds: [max_gamepads + 3]std.posix.pollfd = @splat(.{ .fd = -1, .events = std.posix.POLL.IN, .revents = 0 });
    var repeat: input_repeat.Controller = .{};
    var motion: @import("shelf_motion.zig").Motion = .{};
    var layout_pending = false;
    var press: PressTracker = .{};
    var feedback_lifecycle = ui_components.FeedbackLifecycle{};
    var was_animating = false;
    var save_deadline: ?i64 = null;
    var buffer: [32 * @sizeOf(InputEvent)]u8 align(@alignOf(InputEvent)) = undefined;

    while (true) {
        const now = nowMilliseconds(io);
        if (!feedback_lifecycle.feedback.eql(state.feedback))
            feedback_lifecycle.show(state.feedback, now);
        motion.reduced = state.settings.reduced_motion;
        const repeat_timeout = repeat.timeout(now);
        const animation = (state.page == .games and state.library_view == .browse and motion.active(now)) or presentation.active(now);
        if (animation or was_animating) try display.requestFrame(null);
        var timeout = repeat_timeout;
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
        if (state.page == .wifi or state.page == .wifi_fallback) {
            const captive_wait: i32 = @intCast(@max(0, captive_deadline - now));
            timeout = if (timeout < 0) captive_wait else @min(timeout, captive_wait);
        }
        const feedback_wait = feedback_lifecycle.timeout(now);
        if (feedback_wait >= 0) timeout = if (timeout < 0) feedback_wait else @min(timeout, feedback_wait);
        timeout = interaction_motion.pollTimeout(animation, was_animating, timeout);
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
        _ = try display.poll(&poll_fds, timeout);
        if (save_deadline) |deadline| if (nowMilliseconds(io) >= deadline) {
            saveLibraryPreferences(io, state);
            save_deadline = null;
        };
        var changed = animation or was_animating;
        if (feedback_lifecycle.tick(nowMilliseconds(io))) {
            if (feedback_lifecycle.phase == .hidden) state.feedback = .{};
            changed = true;
        }
        var rescan_inputs = false;
        if ((poll_fds[max_gamepads + 2].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0) return error.InputMonitorUnavailable;
        if ((poll_fds[max_gamepads + 2].revents & std.posix.POLL.IN) != 0) {
            try drainInputMonitor(input_monitor);
            rescan_inputs = true;
        }
        if ((state.page == .wifi or state.page == .wifi_fallback) and
            nowMilliseconds(io) >= captive_deadline)
        {
            changed = refreshCaptive(io, state) or changed;
            captive_deadline = nowMilliseconds(io) + 5000;
        }
        if (nowMilliseconds(io) >= battery_deadline) {
            const percent = batteryPercent(io);
            changed = changed or (state.showsSystemStatus() and percent != state.battery_percent);
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
                state.feedback = .{ .kind = .warning, .message = "Wi-Fi is briefly unavailable" };
                changed = true;
            } else if ((poll_fds[max_gamepads].revents & std.posix.POLL.IN) != 0) {
                var packet: [wifi_ipc.max_packet]u8 = undefined;
                const event = client.receive(&packet) catch {
                    client.close();
                    wifi_client = null;
                    wifi_reconnect_deadline = nowMilliseconds(io) + 1000;
                    state.feedback = .{ .kind = .warning, .message = "Wi-Fi is briefly unavailable" };
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
                        .stale => state.feedback = .{ .kind = .warning, .message = "Wi-Fi changed. Try again." },
                        .rejected => state.feedback = .{ .kind = .failure, .message = "Wi-Fi is unchanged" },
                    },
                }
            }
        }
        if (bluetooth_client) |client| {
            if ((poll_fds[max_gamepads + 1].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0) {
                client.close();
                bluetooth_client = null;
                bluetooth_reconnect_deadline = nowMilliseconds(io) + 1000;
                state.feedback = .{ .kind = .warning, .message = "Bluetooth is briefly unavailable" };
                changed = true;
            } else if ((poll_fds[max_gamepads + 1].revents & std.posix.POLL.IN) != 0) {
                var packet: [bluetooth_ipc.max_packet]u8 = undefined;
                const event = client.receive(&packet) catch {
                    client.close();
                    bluetooth_client = null;
                    bluetooth_reconnect_deadline = nowMilliseconds(io) + 1000;
                    state.feedback = .{ .kind = .warning, .message = "Bluetooth is briefly unavailable" };
                    changed = true;
                    continue;
                };
                switch (event) {
                    .snapshot => |snapshot| changed = state.updateBluetooth(snapshot) or changed,
                    .result => |result| switch (result.status) {
                        .accepted => {},
                        .stale => state.feedback = .{ .kind = .warning, .message = "Bluetooth changed. Try again." },
                        .rejected => state.feedback = .{ .kind = .failure, .message = "Bluetooth is unchanged" },
                    },
                }
            }
        }
        was_animating = animation;
        {
            if (repeat.due(nowMilliseconds(io))) |action| if (repeatAllowed(state, action)) {
                const previous = state.selected;
                const retained_preview = state.library_preview;
                const previous_page = state.page;
                const previous_appearance = state.settings.appearance;
                presentation.cancelNavigation();
                presentation.finishLayout(&tree, nowMilliseconds(io));
                const result = try applySessionAction(io, state, &display, if (wifi_client) |*client| client else null, if (bluetooth_client) |*client| client else null, &bluetooth_request, action);
                // Held navigation updates focus immediately but retains rich
                // content until release, preventing artwork churn from pacing
                // the player's skim.
                if (state.page == .games) state.library_preview = retained_preview;
                const boundary = !result.changed and state.supportsDirection(action) and presentation.focus.boundary(action, nowMilliseconds(io), state.settings.reduced_motion);
                if (wifi_only and state.page != .wifi and state.page != .wifi_fallback) return null;
                if (state.page == .games and state.library_view == .browse and previous != state.selected)
                    motion.retarget(@as(i32, @intCast(state.selected)) - @as(i32, @intCast(previous)), nowMilliseconds(io));
                if (result.launch) |index| {
                    try presentLaunch(io, &display, &tree, state, index);
                    return index;
                }
                if (state.page != previous_page or state.settings.appearance != previous_appearance)
                    tree = beginNavigation(state, nowMilliseconds(io), &presentation);
                layout_pending = layout_pending or (result.changed and state.page == previous_page and directional(action) and !(state.page == .games and state.library_view == .browse));
                changed = changed or result.changed or boundary;
                if (result.changed) save_deadline = nowMilliseconds(io) + 1000;
            };
        }
        for (&gamepads.slots, 0..) |*slot, slot_index| {
            if (slot.fd < 0) continue;
            if ((poll_fds[slot_index].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0) {
                closeFd(io, slot.fd, true);
                slot.* = .{};
                repeat.reset();
                press.clear();
                rescan_inputs = true;
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
                    const settle_preview = event.value == 0 and repeat.repeats != 0 and directionForEvent(event) != null;
                    observeRepeat(&repeat, event, nowMilliseconds(io));
                    if (settle_preview) changed = state.settleLibraryPreview() or changed;
                    const event_action = actionForEvent(event, slot.builtin, &slot.dropped);
                    switch (press.observe(event, slot.builtin, slot.dropped, &tree)) {
                        .pressed => {
                            presentation.cancelNavigation();
                            presentation.finishLayout(&tree, nowMilliseconds(io));
                            changed = true;
                            display.recordInput(event.seconds * 1_000_000 + event.microseconds);
                            continue;
                        },
                        .activated => {
                            const previous = state.selected;
                            const previous_page = state.page;
                            const previous_appearance = state.settings.appearance;
                            presentation.cancelNavigation();
                            presentation.finishLayout(&tree, nowMilliseconds(io));
                            const result = try applySessionAction(io, state, &display, if (wifi_client) |*client| client else null, if (bluetooth_client) |*client| client else null, &bluetooth_request, .select);
                            if (wifi_only and state.page != .wifi and state.page != .wifi_fallback) return null;
                            if (state.page == .games and state.library_view == .browse and previous != state.selected)
                                motion.retarget(@as(i32, @intCast(state.selected)) - @as(i32, @intCast(previous)), nowMilliseconds(io));
                            if (result.launch) |index| {
                                try presentLaunch(io, &display, &tree, state, index);
                                return index;
                            }
                            if (state.page != previous_page or state.settings.appearance != previous_appearance)
                                tree = beginNavigation(state, nowMilliseconds(io), &presentation);
                            changed = changed or result.changed;
                            display.recordInput(event.seconds * 1_000_000 + event.microseconds);
                            if (result.changed) save_deadline = nowMilliseconds(io) + 1000;
                            continue;
                        },
                        .cancelled => changed = true,
                        .none => {},
                    }
                    if (event_action) |action| {
                        const previous = state.selected;
                        const previous_page = state.page;
                        const previous_appearance = state.settings.appearance;
                        presentation.cancelNavigation();
                        presentation.finishLayout(&tree, nowMilliseconds(io));
                        const result = try applySessionAction(io, state, &display, if (wifi_client) |*client| client else null, if (bluetooth_client) |*client| client else null, &bluetooth_request, action);
                        const boundary = !result.changed and state.supportsDirection(action) and presentation.focus.boundary(action, nowMilliseconds(io), state.settings.reduced_motion);
                        if (wifi_only and state.page != .wifi and state.page != .wifi_fallback) return null;
                        if (state.page == .games and state.library_view == .browse and previous != state.selected)
                            motion.retarget(@as(i32, @intCast(state.selected)) - @as(i32, @intCast(previous)), nowMilliseconds(io));
                        if (result.launch) |index| {
                            try presentLaunch(io, &display, &tree, state, index);
                            return index;
                        }
                        if (state.page != previous_page or state.settings.appearance != previous_appearance)
                            tree = beginNavigation(state, nowMilliseconds(io), &presentation);
                        layout_pending = layout_pending or (result.changed and state.page == previous_page and directional(action) and !(state.page == .games and state.library_view == .browse));
                        changed = changed or result.changed or boundary;
                        if (result.changed or boundary) display.recordInput(event.seconds * 1_000_000 + event.microseconds);
                        if (result.changed) save_deadline = nowMilliseconds(io) + 1000;
                    }
                }
                if (bytes_read < buffer.len) break;
            }
        }
        if (rescan_inputs) {
            const inputs_changed = try gamepads.rescan(io);
            if (inputs_changed) {
                repeat.reset();
                press.clear();
            }
            changed = inputs_changed or changed;
            if (!gamepads.hasBuiltin()) return error.GamepadNotFound;
        }
        if (changed) {
            const frame_now = nowMilliseconds(io);
            var next = state.treeWithShelfOffset(motion.offset(frame_now));
            presentation.decorate(&next, frame_now, state.settings.reduced_motion, brightness_meter_id);
            press.decorate(&next);
            if (layout_pending and !presentation.navigation.active(frame_now))
                _ = presentation.layout.begin(&tree, &next, frame_now, state.settings.reduced_motion);
            layout_pending = false;
            tree = next;
            try display.requestFrame(&tree);
        }
        if (display.frameDue()) {
            const frame_now = nowMilliseconds(io);
            tree = state.treeWithShelfOffset(motion.offset(frame_now));
            presentation.decorate(&tree, frame_now, state.settings.reduced_motion, brightness_meter_id);
            press.decorate(&tree);
            if (presentation.navigation.active(frame_now))
                try display.submitTransition(&presentation.navigation, frame_now)
            else if (presentation.layout.active(frame_now)) {
                var frame = presentation.layout.frame(&tree, frame_now);
                try display.submit(&frame);
            } else try display.submit(&tree);
        }
    }
}

fn runOverlay(io: std.Io, state: *overlay.Model) !overlay.Command {
    var console = try Console.open(io);
    defer console.close();
    var display = try Display.open(io, profile_input);
    defer display.close();

    // SAFETY: reset initializes every field before presentation is observed.
    var presentation: scene_motion.Controller = undefined;
    presentation.reset();
    var tree = state.tree();
    presentation.decorate(&tree, nowMilliseconds(io), state.reduced_motion, null);
    try display.show(&tree);
    const input_monitor = try openInputMonitor(input_directory);
    defer closeFd(io, input_monitor, true);
    var gamepads = Gamepads{};
    defer gamepads.close(io);
    _ = try gamepads.rescan(io);
    if (!gamepads.hasBuiltin()) return error.GamepadNotFound;
    if (profile_input) try markReady(io);
    var poll_fds: [max_gamepads + 1]std.posix.pollfd = @splat(.{ .fd = -1, .events = std.posix.POLL.IN, .revents = 0 });
    var repeat: input_repeat.Controller = .{};
    var press: PressTracker = .{};
    var feedback_lifecycle = ui_components.FeedbackLifecycle{};
    var was_animating = false;
    var buffer: [32 * @sizeOf(InputEvent)]u8 align(@alignOf(InputEvent)) = undefined;

    while (true) {
        for (gamepads.slots, 0..) |slot, index| {
            poll_fds[index].fd = slot.fd;
            poll_fds[index].revents = 0;
        }
        poll_fds[max_gamepads].fd = input_monitor;
        poll_fds[max_gamepads].revents = 0;
        const now = nowMilliseconds(io);
        const notice = ui.Feedback{ .kind = state.notice_kind, .message = state.notice };
        if (state.layer != .failure and !feedback_lifecycle.feedback.eql(notice))
            feedback_lifecycle.show(notice, now);
        var repeat_wait = repeat.timeout(now);
        const feedback_wait = feedback_lifecycle.timeout(now);
        if (feedback_wait >= 0) repeat_wait = if (repeat_wait < 0) feedback_wait else @min(repeat_wait, feedback_wait);
        const animation = presentation.active(now);
        const ready = try display.poll(&poll_fds, interaction_motion.pollTimeout(animation, was_animating, repeat_wait));
        var changed = animation or was_animating;
        if (feedback_lifecycle.tick(nowMilliseconds(io))) {
            if (state.layer != .failure) state.notice = "";
            changed = true;
        }
        was_animating = animation;
        var rescan_inputs = false;
        if ((poll_fds[max_gamepads].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0) return error.InputMonitorUnavailable;
        if ((poll_fds[max_gamepads].revents & std.posix.POLL.IN) != 0) {
            try drainInputMonitor(input_monitor);
            rescan_inputs = true;
        }
        if (ready == 0) {
            if (repeat.due(nowMilliseconds(io))) |action| {
                if (action == .up or action == .down) {
                    const applied = state.apply(action);
                    const boundary = !applied and state.supportsDirection(action) and presentation.focus.boundary(action, nowMilliseconds(io), state.reduced_motion);
                    changed = applied or boundary or changed;
                }
            }
        }
        for (&gamepads.slots, 0..) |*slot, slot_index| {
            if (slot.fd < 0) continue;
            if ((poll_fds[slot_index].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL)) != 0) {
                closeFd(io, slot.fd, true);
                slot.* = .{};
                repeat.reset();
                press.clear();
                rescan_inputs = true;
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
                    const event_action = actionForEvent(event, slot.builtin, &slot.dropped);
                    switch (press.observe(event, slot.builtin, slot.dropped, &tree)) {
                        .pressed => {
                            presentation.cancelNavigation();
                            changed = true;
                            display.recordInput(event.seconds * 1_000_000 + event.microseconds);
                            continue;
                        },
                        .activated => {
                            const previous_layer = state.layer;
                            presentation.cancelNavigation();
                            if (state.apply(.select)) changed = true;
                            display.recordInput(event.seconds * 1_000_000 + event.microseconds);
                            const command = state.takeCommand();
                            if (command == null and state.layer != previous_layer)
                                tree = beginOverlayNavigation(state, &tree, previous_layer, .select, nowMilliseconds(io), &presentation);
                            if (command) |resolved| {
                                if (resolved == .save_state or resolved == .load_state) {
                                    var status = ui.message(state.appearance.colors(), if (resolved == .save_state) "Save state" else "Load state", if (resolved == .save_state) "Saving state…" else "Loading state…", "");
                                    try display.show(&status);
                                }
                                return resolved;
                            }
                            continue;
                        },
                        .cancelled => changed = true,
                        .none => {},
                    }
                    if (event_action) |action| {
                        const previous_layer = state.layer;
                        presentation.cancelNavigation();
                        const applied = state.apply(action);
                        const boundary = !applied and state.supportsDirection(action) and presentation.focus.boundary(action, nowMilliseconds(io), state.reduced_motion);
                        if (applied or boundary) {
                            changed = true;
                            display.recordInput(event.seconds * 1_000_000 + event.microseconds);
                        }
                        const command = state.takeCommand();
                        if (command == null and state.layer != previous_layer)
                            tree = beginOverlayNavigation(state, &tree, previous_layer, action, nowMilliseconds(io), &presentation);
                        if (command) |resolved| {
                            if (resolved == .save_state or resolved == .load_state) {
                                var status = ui.message(state.appearance.colors(), if (resolved == .save_state) "Save state" else "Load state", if (resolved == .save_state) "Saving state…" else "Loading state…", "");
                                try display.show(&status);
                            }
                            return resolved;
                        }
                    }
                }
                if (bytes_read < buffer.len) break;
            }
        }
        if (rescan_inputs) {
            if (try gamepads.rescan(io)) {
                repeat.reset();
                press.clear();
            }
            if (!gamepads.hasBuiltin()) return error.GamepadNotFound;
        }
        if (changed) {
            const frame_now = nowMilliseconds(io);
            tree = state.tree();
            presentation.decorate(&tree, frame_now, state.reduced_motion, null);
            press.decorate(&tree);
            try display.requestFrame(&tree);
        }
        if (display.frameDue()) {
            const frame_now = nowMilliseconds(io);
            tree = state.tree();
            presentation.decorate(&tree, frame_now, state.reduced_motion, null);
            press.decorate(&tree);
            if (presentation.navigation.active(frame_now))
                try display.submitTransition(&presentation.navigation, frame_now)
            else
                try display.submit(&tree);
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

pub fn run(io: std.Io, profile: ?Profile) !void {
    profile_input = profile != null;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const initial_settings = settings.load(io);
    {
        var console = try Console.open(io);
        defer console.close();
        var display = try Display.open(io, profile_input);
        defer display.close();
        var splash = ui.splash(initial_settings.appearance.colors());
        try display.show(&splash);
    }
    if (profile == .overlay) {
        var game_overlay = overlay.Model{ .appearance = initial_settings.appearance, .reduced_motion = initial_settings.reduced_motion, .title = "Input regression" };
        std.log.info("UI profile: overlay", .{});
        const command = try runOverlay(io, &game_overlay);
        std.log.info("UI overlay profile: command={s}", .{@tagName(command)});
        return;
    }
    const library = try catalog.discover(io, arena.allocator(), "/data");
    var state = model.Model{ .games = library, .settings = initial_settings };
    if (std.Io.Dir.cwd().openDir(io, "/data/settings", .{})) |dir| {
        defer dir.close(io);
        @import("library_preferences.zig").load(io, dir, &state);
    } else |_| {}
    if (profile) |page| switch (page) {
        .settings => state.page = .settings,
        .shelf => state = .{ .games = &catalog.games, .page = .games, .library_view = .browse, .settings = initial_settings },
        .overlay => {},
    };
    if (profile) |page| std.log.info("UI profile: {s} games={d}", .{ @tagName(page), state.games.len });
    if (state.last_played) |index| {
        if (index < state.games.len)
            state.resumable = retroarch.availableStates(io, &state.games[index])[3];
    }
    var boot_game: ?usize = if (profile == null) state.bootTarget() else null;
    while (true) {
        const game_index = boot_game orelse (try runSession(io, &state, false)) orelse continue;
        boot_game = null;
        const game = &state.games[game_index];
        var game_overlay = overlay.Model{
            .appearance = state.settings.appearance,
            .reduced_motion = state.settings.reduced_motion,
            .title = game.title,
            .system = game.system,
            .game = game.*,
            .brightness = state.settings.brightness,
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
            if (retroarch.takeAudioLoss()) {
                game_overlay.notice = "Bluetooth audio disconnected. Reconnect it, then relaunch the game.";
                game_overlay.notice_kind = .failure;
            }
            while (true) {
                refreshWifi(&state);
                game_overlay.network_status = state.wifi.wifi_state.snapshot.settingsSummary();
                game_overlay.battery_percent = batteryPercent(io);
                game_overlay.network_indicator = switch (state.wifi.wifi_state.snapshot.connectivity) {
                    .internet => .connected,
                    .local, .captive, .limited => .attention,
                    .none => .hidden,
                };
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
                            game_overlay.notice_kind = .failure;
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
                            game_overlay.notice_kind = .failure;
                            std.log.err("Failed to save state: {s}", .{@errorName(err)});
                            continue;
                        };
                        game_overlay.layer = .pause;
                        game_overlay.selected = 1;
                        game_overlay.saved = true;
                        game_overlay.notice = "State saved";
                        game_overlay.notice_kind = .success;
                    },
                    .load_state => {
                        retroarch.loadState(io, game, state.games, game_overlay.state_slot) catch |err| {
                            game_overlay.layer = .states;
                            game_overlay.notice = "Could not load that saved state";
                            game_overlay.notice_kind = .failure;
                            std.log.err("Failed to load state: {s}", .{@errorName(err)});
                            continue;
                        };
                        game_overlay.notice = "";
                        game_overlay.layer = .pause;
                        game_overlay.selected = 0;
                        continue :game_session;
                    },
                    .apply_brightness => {
                        state.settings.brightness = game_overlay.brightness;
                        settings.apply(io, state.settings, .brightness) catch |err| {
                            state.settings = settings.load(io);
                            game_overlay.brightness = state.settings.brightness;
                            game_overlay.notice = "Brightness did not change";
                            game_overlay.notice_kind = .failure;
                            std.log.err("Failed to apply brightness: {s}", .{@errorName(err)});
                        };
                    },
                    .network_settings => {
                        state.page = .wifi;
                        state.selected = 0;
                        state.wifi.page = .list;
                        _ = try runSession(io, &state, true);
                        const resume_game = state.page == .games;
                        state.page = .games;
                        state.selected = 0;
                        if (resume_game) {
                            game_overlay.layer = .pause;
                            game_overlay.selected = 0;
                            continue :game_session;
                        }
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
    var display = try Display.open(io, profile_input);
    defer display.close();
    var gamepads = Gamepads{};
    defer gamepads.close(io);
    _ = try gamepads.rescan(io);
    if (!gamepads.hasBuiltin()) return error.GamepadNotFound;
    var state = model.Model{};
    var tree = state.tree();
    try display.show(&tree);
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

test "select press decorates before release activates" {
    const theme = @import("theme.zig").light;
    var tree = ui.Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .menu_row = .{ .bounds = .{ .x = 0, .y = 0, .width = 200, .height = 88 }, .label = "Play", .selected = true } });
    var press: PressTracker = .{};
    const down = InputEvent{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_east, .value = 1 };
    try std.testing.expectEqual(PressResult.pressed, press.observe(down, true, false, &tree));
    press.decorate(&tree);
    try std.testing.expectEqual(interaction.State.pressed, tree.elements[0].menu_row.state);
    const up = InputEvent{ .seconds = 0, .microseconds = 0, .event_type = ev_key, .code = btn_east, .value = 0 };
    try std.testing.expectEqual(PressResult.activated, press.observe(up, true, false, &tree));
    try std.testing.expect(press.id == null);
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

fn writeInputFixture(dir: std.Io.Dir, index: u8, builtin: bool) !void {
    const io = std.testing.io;
    var buffer: [128]u8 = undefined;
    try dir.createDirPath(io, try std.fmt.bufPrint(&buffer, "sysfs/event{d}/device/capabilities", .{index}));
    try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&buffer, "sysfs/event{d}/device/name", .{index}), .data = if (builtin) "TrimUI Brick Gamepad" else "Fixture gamepad" });
    var keys: [btn_south / 4 + 1]u8 = @splat('0');
    keys[0] = '1';
    try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&buffer, "sysfs/event{d}/device/capabilities/key", .{index}), .data = &keys });
    try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&buffer, "input/event{d}", .{index}), .data = "" });
}

test "input watch catches startup hotplug removal and reconnection without a timer" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(io, ".", allocator);
    try temporary.dir.createDirPath(io, "input");
    try temporary.dir.createDirPath(io, "sysfs");
    const paths = InputPaths{
        .devices = try std.fmt.allocPrint(allocator, "{s}/input", .{root}),
        .sysfs = try std.fmt.allocPrint(allocator, "{s}/sysfs", .{root}),
    };
    const monitor = try openInputMonitor(try allocator.dupeSentinel(u8, paths.devices, 0));
    defer closeFd(io, monitor, true);
    var gamepads = Gamepads{};
    defer gamepads.close(io);
    try std.testing.expect(!try gamepads.rescanAt(io, paths));
    try writeInputFixture(temporary.dir, 2, true);
    var fds = [_]std.posix.pollfd{.{ .fd = monitor, .events = std.posix.POLL.IN, .revents = 0 }};
    try std.testing.expectEqual(@as(usize, 1), try std.posix.poll(&fds, 100));
    try drainInputMonitor(monitor);
    try std.testing.expect(try gamepads.rescanAt(io, paths));
    try std.testing.expect(gamepads.hasBuiltin());
    const builtin_fd = gamepads.slots[0].fd;
    try std.testing.expect(!try gamepads.rescanAt(io, paths));
    try std.testing.expectEqual(builtin_fd, gamepads.slots[0].fd);
    for (0..3) |_| {
        try writeInputFixture(temporary.dir, 3, false);
        try std.testing.expectEqual(@as(usize, 1), try std.posix.poll(&fds, 100));
        try drainInputMonitor(monitor);
        try std.testing.expect(try gamepads.rescanAt(io, paths));
        try std.testing.expect(gamepads.hasIndex(3));
        try temporary.dir.deleteFile(io, "input/event3");
        try temporary.dir.deleteTree(io, "sysfs/event3");
        try std.testing.expectEqual(@as(usize, 1), try std.posix.poll(&fds, 100));
        try drainInputMonitor(monitor);
        try std.testing.expect(try gamepads.rescanAt(io, paths));
        try std.testing.expect(!gamepads.hasIndex(3));
        try std.testing.expectEqual(builtin_fd, gamepads.slots[0].fd);
    }
    try std.testing.expectEqual(@as(usize, 0), try std.posix.poll(&fds, 0));
}

test "input notification overflow permits reconciliation but lost watches fail" {
    var event = InputMonitorEvent{ .watch = -1, .mask = std.os.linux.IN.Q_OVERFLOW, .cookie = 0, .name_len = 0 };
    try checkInputMonitorEvents(std.mem.asBytes(&event));
    event.mask = std.os.linux.IN.IGNORED;
    try std.testing.expectError(error.InputMonitorUnavailable, checkInputMonitorEvents(std.mem.asBytes(&event)));
    event.mask = std.os.linux.IN.CREATE;
    event.name_len = 16;
    try std.testing.expectError(error.InvalidInputMonitorEvent, checkInputMonitorEvents(std.mem.asBytes(&event)));
    try std.testing.expectError(error.InvalidInputMonitorEvent, checkInputMonitorEvents(&.{0}));
}

test "removing the watched input directory is detected" {
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(io, "input");
    const root = try temporary.dir.realPathFileAlloc(io, "input", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const path = try std.testing.allocator.dupeSentinel(u8, root, 0);
    defer std.testing.allocator.free(path);
    const monitor = try openInputMonitor(path);
    defer closeFd(io, monitor, true);
    try temporary.dir.deleteTree(io, "input");
    var fds = [_]std.posix.pollfd{.{ .fd = monitor, .events = std.posix.POLL.IN, .revents = 0 }};
    try std.testing.expectEqual(@as(usize, 1), try std.posix.poll(&fds, 100));
    try std.testing.expectError(error.InputMonitorUnavailable, drainInputMonitor(monitor));
}
