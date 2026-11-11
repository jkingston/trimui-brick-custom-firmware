// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const input = @import("input.zig");
const Field = @import("wifi_flow.zig").Field;

pub const max_devices = 32;
pub const max_name_bytes = 96;
pub const max_identity_bytes = 64;

pub const RadioState = enum { unavailable, off, starting, ready, stopping, failed };
pub const DiscoveryState = enum { idle, classic, low_energy, paused, failed };
pub const DeviceKind = enum { controller, audio, other };
pub const DeviceState = enum { nearby, saved, connected, preparing_audio, ready };
pub const Operation = enum { none, radio_change, discovery, pairing, connection, disconnection, forget };
pub const Prompt = enum { none, confirm, pin, passkey, display_pin, display_passkey };

pub const Text = struct {
    bytes: [max_name_bytes]u8 = @splat(0),
    len: u8 = 0,
    pub fn slice(self: *const Text) []const u8 {
        return self.bytes[0..self.len];
    }
    pub fn set(self: *Text, value: []const u8) !void {
        if (value.len > self.bytes.len or !std.unicode.utf8ValidateSlice(value)) return error.InvalidText;
        @memcpy(self.bytes[0..value.len], value);
        self.len = @intCast(value.len);
    }
};

pub const Identity = struct {
    bytes: [max_identity_bytes]u8 = @splat(0),
    len: u8 = 0,
    pub fn slice(self: *const Identity) []const u8 {
        return self.bytes[0..self.len];
    }
    pub fn eql(a: Identity, b: Identity) bool {
        return std.mem.eql(u8, a.slice(), b.slice());
    }
    pub fn set(self: *Identity, value: []const u8) !void {
        if (value.len == 0 or value.len > self.bytes.len) return error.InvalidIdentity;
        for (value) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_') return error.InvalidIdentity;
        @memcpy(self.bytes[0..value.len], value);
        self.len = @intCast(value.len);
    }
};

pub const Device = struct {
    id: Identity = .{},
    name: Text = .{},
    kind: DeviceKind = .other,
    state: DeviceState = .nearby,
    battery: ?u8 = null,
    battery_label: Text = .{},
    legacy: bool = false,
    pub fn detail(self: Device) []const u8 {
        return switch (self.state) {
            .nearby => switch (self.kind) {
                .controller => "Nearby controller",
                .audio => "Nearby audio device",
                .other => "Nearby device",
            },
            .saved => "Saved",
            .connected => "Connected",
            .preparing_audio => "Preparing audio…",
            .ready => if (self.kind == .audio) "Audio ready" else "Connected",
        };
    }
};

pub const Snapshot = struct {
    generation: u32 = 0,
    revision: u32 = 0,
    radio: RadioState = .unavailable,
    discovery: DiscoveryState = .idle,
    operation: Operation = .none,
    operation_device: Identity = .{},
    prompt: Prompt = .none,
    prompt_device: Identity = .{},
    prompt_value: [16]u8 = @splat(0),
    prompt_value_len: u8 = 0,
    devices: [max_devices]Device = @splat(.{}),
    device_count: u8 = 0,
    pub fn items(self: *const Snapshot) []const Device {
        return self.devices[0..self.device_count];
    }
    pub fn find(self: *const Snapshot, id: Identity) ?usize {
        for (self.items(), 0..) |device, index| if (Identity.eql(device.id, id)) return index;
        return null;
    }
    pub fn summary(self: Snapshot) []const u8 {
        return switch (self.radio) {
            .unavailable => "Unavailable",
            .failed => "Needs attention",
            .off => "Off",
            .stopping => "Stopping…",
            .starting => "Starting…",
            .ready => "On",
        };
    }
    pub fn status(self: Snapshot) []const u8 {
        return switch (self.radio) {
            .unavailable => "Bluetooth unavailable",
            .off => "Bluetooth off",
            .starting => "Turning Bluetooth on…",
            .stopping => "Turning Bluetooth off…",
            .failed => "Bluetooth unavailable",
            .ready => switch (self.operation) {
                .pairing => "Pairing device…",
                .connection => "Connecting device…",
                .disconnection => "Disconnecting device…",
                .forget => "Forgetting device…",
                .radio_change => "Changing Bluetooth state…",
                .discovery, .none => switch (self.discovery) {
                    .classic, .low_energy, .paused => "Looking for devices…",
                    .failed => "Device search failed",
                    .idle => "Choose a device",
                },
            },
        };
    }
};

pub const CommandKind = enum { set_radio, start_search, cancel, pair, connect, disconnect, forget, select_audio, confirm_pairing, submit_passkey, network_activity };
pub const Command = struct {
    generation: u32,
    request_id: u32,
    kind: CommandKind,
    device: ?Identity = null,
    value: bool = false,
    secret: [96]u8 = @splat(0),
    secret_len: u8 = 0,
    pub fn wipe(self: *Command) void {
        std.crypto.secureZero(u8, &self.secret);
        self.secret_len = 0;
    }
};
pub const Page = enum { list, details, forget_confirm, confirmation, code_entry, code_display };

pub const Model = struct {
    snapshot: Snapshot = .{},
    initialized: bool = false,
    page: Page = .list,
    selected: usize = 0,
    active: ?Identity = null,
    detail_selected: usize = 0,
    confirm_selected: usize = 0,
    field: Field = .{},
    pending: ?Command = null,
    next_request_id: u32 = 1,
    pub fn update(self: *Model, next: Snapshot) bool {
        if (next.generation < self.snapshot.generation or (next.generation == self.snapshot.generation and next.revision <= self.snapshot.revision)) return false;
        self.initialized = true;
        const focused = if (self.page == .list and self.selected > 0 and self.selected <= self.snapshot.device_count)
            self.snapshot.devices[self.selected - 1].id
        else
            null;
        const restarted = self.snapshot.generation != 0 and next.generation != self.snapshot.generation;
        self.snapshot = next;
        if (restarted) {
            self.page = .list;
            self.active = null;
            self.field.wipe();
            self.clearPending();
        }
        if (next.prompt != .none) {
            self.active = next.prompt_device;
            self.page = switch (next.prompt) {
                .confirm => .confirmation,
                .pin, .passkey => .code_entry,
                .display_pin, .display_passkey => .code_display,
                .none => .list,
            };
        } else if (self.page == .confirmation or self.page == .code_entry or self.page == .code_display) {
            self.page = .list;
            self.field.wipe();
        }
        if (focused) |id| {
            if (next.find(id)) |index|
                self.selected = index + 1
            else
                self.selected = @min(self.selected, self.itemCount() -| 1);
        } else self.selected = @min(self.selected, self.itemCount() -| 1);
        return true;
    }

    pub fn summary(self: *const Model) []const u8 {
        return if (self.initialized) self.snapshot.summary() else "Checking…";
    }

    pub fn status(self: *const Model) []const u8 {
        return if (self.initialized) self.snapshot.status() else "Checking Bluetooth…";
    }
    pub fn activeDevice(self: *const Model) ?*const Device {
        const id = self.active orelse return null;
        const index = self.snapshot.find(id) orelse return null;
        return &self.snapshot.devices[index];
    }
    pub fn itemCount(self: *const Model) usize {
        if (self.snapshot.radio != .ready) return 1;
        return 2 + self.snapshot.device_count;
    }
    fn queue(self: *Model, kind: CommandKind, device: ?Identity, value: bool) void {
        self.clearPending();
        self.pending = .{ .generation = self.snapshot.generation, .request_id = self.next_request_id, .kind = kind, .device = device, .value = value };
        self.next_request_id +%= 1;
        if (self.next_request_id == 0) self.next_request_id = 1;
    }
    pub fn apply(self: *Model, action: input.Action) bool {
        return switch (self.page) {
            .list => self.applyList(action),
            .details => self.applyDetails(action),
            .forget_confirm, .confirmation => self.applyConfirmation(action),
            .code_entry => self.applyCode(action),
            .code_display => self.applyDisplay(action),
        };
    }

    /// Menu dismisses the complete system layer. Resolve interactive pairing
    /// prompts and cancel invisible work before their UI disappears.
    pub fn dismiss(self: *Model) void {
        if (self.page == .confirmation or self.page == .code_entry or self.page == .code_display) {
            _ = self.apply(.back);
        } else if (self.snapshot.operation != .none and self.snapshot.operation != .discovery) {
            self.queue(.cancel, if (self.snapshot.operation_device.len == 0) null else self.snapshot.operation_device, false);
        } else if (self.snapshot.discovery != .idle) {
            self.queue(.cancel, null, false);
        } else self.clearPending();
        self.field.wipe();
        self.page = .list;
        self.active = null;
        self.selected = 0;
        self.detail_selected = 0;
        self.confirm_selected = 0;
    }
    fn applyList(self: *Model, action: input.Action) bool {
        const cancellable = self.snapshot.operation != .none and self.snapshot.operation != .discovery;
        if (cancellable) {
            if (action != .back) return false;
            self.queue(.cancel, if (self.snapshot.operation_device.len == 0) null else self.snapshot.operation_device, false);
            return true;
        }
        switch (action) {
            .up => {
                const before = self.selected;
                self.selected -|= 1;
                return before != self.selected;
            },
            .down => {
                const before = self.selected;
                self.selected = @min(self.selected + 1, self.itemCount() -| 1);
                return before != self.selected;
            },
            .filter => {
                if (self.snapshot.radio != .ready) return false;
                self.queue(if (self.snapshot.discovery == .idle) .start_search else .cancel, null, false);
            },
            .select => {
                if (self.selected == 0) {
                    const enable = switch (self.snapshot.radio) {
                        .off, .failed => true,
                        .ready, .starting => false,
                        else => return false,
                    };
                    self.queue(.set_radio, null, enable);
                } else if (self.selected <= self.snapshot.device_count) {
                    const device = self.snapshot.devices[self.selected - 1];
                    self.active = device.id;
                    switch (device.state) {
                        .nearby => self.queue(.pair, device.id, false),
                        .saved => self.queue(.connect, device.id, false),
                        .connected, .preparing_audio, .ready => {
                            self.page = .details;
                            self.detail_selected = 0;
                        },
                    }
                } else self.queue(if (self.snapshot.discovery == .idle) .start_search else .cancel, null, false);
            },
            else => return false,
        }
        return true;
    }
    fn applyDetails(self: *Model, action: input.Action) bool {
        const device = self.activeDevice() orelse {
            self.page = .list;
            return true;
        };
        const max: usize = if (device.kind == .audio and device.state == .ready) 2 else 1;
        switch (action) {
            .up => {
                const before = self.detail_selected;
                self.detail_selected -|= 1;
                return before != self.detail_selected;
            },
            .down => {
                const before = self.detail_selected;
                self.detail_selected = @min(max, self.detail_selected + 1);
                return before != self.detail_selected;
            },
            .back => {
                self.page = .list;
                self.detail_selected = 0;
            },
            .select => if (self.detail_selected == 0) {
                self.queue(if (device.state == .saved) .connect else .disconnect, device.id, false);
                self.page = .list;
            } else if (device.kind == .audio and device.state == .ready and self.detail_selected == 1) self.queue(.select_audio, device.id, true) else {
                self.page = .forget_confirm;
                self.confirm_selected = 0;
            },
            else => return false,
        }
        return true;
    }
    fn applyConfirmation(self: *Model, action: input.Action) bool {
        switch (action) {
            .left, .right, .up, .down => self.confirm_selected = 1 - self.confirm_selected,
            .back => {
                if (self.page == .confirmation) self.queue(.confirm_pairing, self.active, false);
                self.page = if (self.page == .forget_confirm) .details else .list;
            },
            .select => {
                if (self.page == .confirmation) {
                    self.queue(.confirm_pairing, self.active, self.confirm_selected == 1);
                    self.page = .list;
                } else if (self.confirm_selected == 1) {
                    self.queue(.forget, self.active, false);
                    self.page = .list;
                    self.active = null;
                } else self.page = .details;
                self.confirm_selected = 0;
            },
            else => return false,
        }
        return true;
    }
    fn applyCode(self: *Model, action: input.Action) bool {
        switch (action) {
            .up, .down, .left, .right => return self.field.move(action),
            .back => {
                self.queue(.cancel, self.active, false);
                self.field.wipe();
                self.page = .list;
            },
            .select => switch (self.field.activate()) {
                .unchanged => return false,
                .changed => return true,
                .submit => {
                    if (self.field.len == 0) return false;
                    self.queue(.submit_passkey, self.active, false);
                    @memcpy(self.pending.?.secret[0..self.field.len], self.field.slice());
                    self.pending.?.secret_len = self.field.len;
                    self.field.wipe();
                    self.page = .list;
                },
            },
            else => return false,
        }
        return true;
    }
    fn applyDisplay(self: *Model, action: input.Action) bool {
        if (action != .back and action != .select) return false;
        if (action == .back) self.queue(.cancel, self.active, false);
        self.page = .list;
        return true;
    }
    fn clearPending(self: *Model) void {
        if (self.pending) |*command| command.wipe();
        self.pending = null;
    }
    pub fn takeCommand(self: *Model) ?Command {
        const command = self.pending orelse return null;
        self.pending = null;
        return command;
    }
};

fn parseEnum(comptime T: type, value: []const u8) !T {
    inline for (@typeInfo(T).@"enum".field_names, @typeInfo(T).@"enum".field_values) |name, field_value| if (std.mem.eql(u8, value, name)) return @fromBackingInt(@intCast(field_value));
    return error.InvalidEnum;
}
fn decodeHex(output: []u8, value: []const u8) ![]const u8 {
    if (value.len % 2 != 0 or value.len / 2 > output.len) return error.InvalidHex;
    for (0..value.len / 2) |index| output[index] = try std.fmt.parseInt(u8, value[index * 2 .. index * 2 + 2], 16);
    return output[0 .. value.len / 2];
}
fn field(line: []const u8, name: []const u8) ?[]const u8 {
    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    while (tokens.next()) |token| {
        const equals = std.mem.indexOfScalar(u8, token, '=') orelse continue;
        if (std.mem.eql(u8, token[0..equals], name)) return token[equals + 1 ..];
    }
    return null;
}
pub fn parse(packet: []const u8) !Snapshot {
    var lines = std.mem.splitScalar(u8, packet, '\n');
    const header = lines.next() orelse return error.InvalidSnapshot;
    if (!std.mem.startsWith(u8, header, "snapshot ")) return error.InvalidSnapshot;
    if (try std.fmt.parseInt(u8, field(header, "version") orelse return error.InvalidSnapshot, 10) != 1) return error.InvalidVersion;
    var result = Snapshot{ .generation = try std.fmt.parseInt(u32, field(header, "generation") orelse return error.InvalidSnapshot, 10), .revision = try std.fmt.parseInt(u32, field(header, "revision") orelse return error.InvalidSnapshot, 10), .radio = try parseEnum(RadioState, field(header, "radio") orelse return error.InvalidSnapshot), .discovery = try parseEnum(DiscoveryState, field(header, "discovery") orelse return error.InvalidSnapshot), .operation = try parseEnum(Operation, field(header, "operation") orelse return error.InvalidSnapshot), .prompt = try parseEnum(Prompt, field(header, "prompt") orelse return error.InvalidSnapshot) };
    const operation_device = field(header, "operation_device") orelse "";
    if (operation_device.len != 0) try result.operation_device.set(operation_device);
    const prompt_device = field(header, "prompt_device") orelse "";
    if (prompt_device.len != 0) try result.prompt_device.set(prompt_device);
    const prompt_value = field(header, "prompt_value") orelse "";
    if (prompt_value.len > result.prompt_value.len) return error.InvalidSnapshot;
    @memcpy(result.prompt_value[0..prompt_value.len], prompt_value);
    result.prompt_value_len = @intCast(prompt_value.len);
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "end")) return result;
        if (line.len == 0) continue;
        if (!std.mem.startsWith(u8, line, "device ") or result.device_count == max_devices) return error.InvalidSnapshot;
        var device = Device{};
        try device.id.set(field(line, "id") orelse return error.InvalidSnapshot);
        var decoded: [max_name_bytes]u8 = undefined;
        try device.name.set(try decodeHex(&decoded, field(line, "name_hex") orelse return error.InvalidSnapshot));
        device.kind = try parseEnum(DeviceKind, field(line, "kind") orelse return error.InvalidSnapshot);
        device.state = try parseEnum(DeviceState, field(line, "state") orelse return error.InvalidSnapshot);
        const battery = try std.fmt.parseInt(i16, field(line, "battery") orelse "-1", 10);
        if (battery >= 0 and battery <= 100) {
            device.battery = @intCast(battery);
            var label: [5]u8 = undefined;
            try device.battery_label.set(try std.fmt.bufPrint(&label, "{d}%", .{battery}));
        }
        device.legacy = std.mem.eql(u8, field(line, "legacy") orelse "0", "1");
        result.devices[result.device_count] = device;
        result.device_count += 1;
    }
    return error.UnterminatedSnapshot;
}

test "snapshot uses opaque ids and optional battery" {
    const packet = "snapshot version=1 generation=9 revision=3 radio=ready discovery=idle operation=none operation_device= prompt=none prompt_device= prompt_value=\n" ++ "device id=0123456789abcdef0123456789abcdef name_hex=47616d65706164 kind=controller state=connected battery=73 legacy=0\nend\n";
    const snapshot = try parse(packet);
    try std.testing.expectEqualStrings("Gamepad", snapshot.devices[0].name.slice());
    try std.testing.expectEqual(@as(?u8, 73), snapshot.devices[0].battery);
}

test "failed radio is distinct from unavailable radio" {
    var snapshot = Snapshot{ .radio = .unavailable };
    try std.testing.expectEqualStrings("Unavailable", snapshot.summary());
    snapshot.radio = .failed;
    try std.testing.expectEqualStrings("Needs attention", snapshot.summary());
}

test "startup is checking until the authority supplies a snapshot" {
    var state = Model{};
    try std.testing.expect(!state.initialized);
    try std.testing.expectEqualStrings("Checking…", state.summary());
    try std.testing.expectEqualStrings("Checking Bluetooth…", state.status());
    try std.testing.expect(state.update(.{ .generation = 1, .revision = 1, .radio = .unavailable }));
    try std.testing.expect(state.initialized);
    try std.testing.expectEqualStrings("Unavailable", state.summary());
}
test "an in-flight device operation accepts only explicit cancellation" {
    var model = Model{};
    const snapshot = try parse("snapshot version=1 generation=1 revision=1 radio=ready discovery=idle operation=connection operation_device=pad prompt=none prompt_device= prompt_value=\n" ++
        "device id=pad name_hex=47616d65706164 kind=controller state=saved battery=-1 legacy=0\nend\n");
    try std.testing.expect(model.update(snapshot));
    try std.testing.expect(!model.apply(.select));
    try std.testing.expect(model.apply(.back));
    const command = model.takeCommand().?;
    try std.testing.expectEqual(CommandKind.cancel, command.kind);
    try std.testing.expect(Identity.eql(snapshot.operation_device, command.device.?));
}
test "list reports saturated movement as a boundary" {
    var model = Model{};
    try std.testing.expect(!model.apply(.up));
    try std.testing.expect(!model.apply(.down));
}
test "pairing prompt routes through confirmation" {
    var model = Model{};
    const snapshot = try parse("snapshot version=1 generation=1 revision=1 radio=ready discovery=idle operation=pairing operation_device=abc prompt=confirm prompt_device=abc prompt_value=123456\nend\n");
    try std.testing.expect(model.update(snapshot));
    try std.testing.expectEqual(Page.confirmation, model.page);
    _ = model.apply(.right);
    _ = model.apply(.select);
    try std.testing.expectEqual(CommandKind.confirm_pairing, model.takeCommand().?.kind);
}

test "focused device survives server-side group reordering" {
    var model = Model{};
    const first = try parse("snapshot version=1 generation=1 revision=1 radio=ready discovery=idle operation=none operation_device= prompt=none prompt_device= prompt_value=\n" ++
        "device id=aaa name_hex=41 kind=controller state=nearby battery=-1 legacy=0\n" ++
        "device id=bbb name_hex=42 kind=controller state=nearby battery=-1 legacy=0\nend\n");
    try std.testing.expect(model.update(first));
    model.selected = 2;
    const reordered = try parse("snapshot version=1 generation=1 revision=2 radio=ready discovery=idle operation=none operation_device= prompt=none prompt_device= prompt_value=\n" ++
        "device id=bbb name_hex=42 kind=controller state=connected battery=-1 legacy=0\n" ++
        "device id=aaa name_hex=41 kind=controller state=nearby battery=-1 legacy=0\nend\n");
    try std.testing.expect(model.update(reordered));
    try std.testing.expectEqual(@as(usize, 1), model.selected);
}
