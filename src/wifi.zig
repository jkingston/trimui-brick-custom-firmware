// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const max_networks = 32;
pub const max_name_bytes = 128;
pub const max_identity_bytes = 64;

pub const RadioState = enum { unavailable, off, starting, ready, stopping, failed };
pub const Connectivity = enum { none, local, captive, internet, limited };
pub const Security = enum { open, wpa2_personal, unsupported };
pub const Signal = enum { weak, fair, good, strong };
pub const NetworkState = enum {
    available,
    saved,
    connecting,
    validating,
    connected,
    sign_in,
    limited,
    reconnecting,
    auth_failed,
    address_failed,
    out_of_range,
    unsupported,
};

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

    pub fn setScanName(self: *Text, value: []const u8) !void {
        if (std.unicode.utf8ValidateSlice(value)) return self.set(value);
        const hex = "0123456789abcdef";
        if (value.len * 4 > self.bytes.len) return error.InvalidText;
        for (value, 0..) |byte, index| {
            self.bytes[index * 4] = '\\';
            self.bytes[index * 4 + 1] = 'x';
            self.bytes[index * 4 + 2] = hex[byte >> 4];
            self.bytes[index * 4 + 3] = hex[byte & 0xf];
        }
        self.len = @intCast(value.len * 4);
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

    fn set(self: *Identity, value: []const u8) !void {
        if (value.len == 0 or value.len > self.bytes.len) return error.InvalidIdentity;
        for (value) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_') return error.InvalidIdentity;
        @memcpy(self.bytes[0..value.len], value);
        self.len = @intCast(value.len);
    }
};

pub const Network = struct {
    id: Identity = .{},
    name: Text = .{},
    security: Security = .unsupported,
    signal: Signal = .weak,
    state: NetworkState = .available,
    saved: bool = false,
    current: bool = false,
    in_range: bool = true,
    auto_connect: bool = false,
    private_address: bool = true,
    address: Text = .{},
};

pub const Snapshot = struct {
    generation: u32 = 0,
    revision: u32 = 0,
    radio: RadioState = .unavailable,
    connectivity: Connectivity = .none,
    can_scan: bool = false,
    networks: [max_networks]Network = @splat(.{}),
    network_count: u8 = 0,

    pub fn items(self: *const Snapshot) []const Network {
        return self.networks[0..self.network_count];
    }

    pub fn find(self: *const Snapshot, id: Identity) ?usize {
        for (self.items(), 0..) |network, index| if (Identity.eql(network.id, id)) return index;
        return null;
    }

    pub fn settingsSummary(self: Snapshot) []const u8 {
        return switch (self.radio) {
            .unavailable, .failed => "Unavailable",
            .off, .stopping => "Off",
            .starting => "On",
            .ready => switch (self.connectivity) {
                .captive => "Sign-in required",
                .limited => "No internet",
                else => "On",
            },
        };
    }

    pub fn status(self: *const Snapshot) []const u8 {
        return switch (self.radio) {
            .unavailable => "Wi-Fi unavailable",
            .off => "Wi-Fi off",
            .starting => "Turning Wi-Fi on\xe2\x80\xa6",
            .stopping => "Turning Wi-Fi off\xe2\x80\xa6",
            .failed => "Wi-Fi could not start",
            .ready => self.currentStatus(),
        };
    }

    fn currentStatus(self: *const Snapshot) []const u8 {
        for (self.items()) |network| if (network.current) return stateDetail(network.state);
        return "Choose a network";
    }
};

pub const CommandKind = enum {
    set_enabled,
    scan,
    connect,
    cancel,
    disconnect,
    forget,
    set_auto_connect,
    set_private_address,
    open_captive,
    recheck,
};

pub const Command = struct {
    generation: u32,
    request_id: u32,
    kind: CommandKind,
    network: ?Identity = null,
    value: bool = false,
};

pub const Model = struct {
    snapshot: Snapshot = .{},
    selected: usize = 0,
    focused: ?Identity = null,
    pending: ?Command = null,
    next_request_id: u32 = 1,
    freeze_order: bool = false,

    pub fn update(self: *Model, next: Snapshot) bool {
        if (next.generation < self.snapshot.generation) return false;
        if (next.generation == self.snapshot.generation and next.revision <= self.snapshot.revision) return false;

        const previous_focus = self.focused;
        self.snapshot = if (self.freeze_order and next.generation == self.snapshot.generation)
            stableOrder(self.snapshot, next)
        else
            next;
        if (previous_focus) |identity| {
            if (self.snapshot.find(identity)) |index| {
                self.selected = index + 1;
                self.focused = identity;
            } else {
                self.selected = @min(self.selected, self.itemCount() -| 1);
                self.updateFocus();
            }
        } else {
            self.selected = @min(self.selected, self.itemCount() -| 1);
            self.updateFocus();
        }
        return true;
    }

    /// Scans may update values while the user is moving through the list, but
    /// must not move the row under their thumb. The caller releases the order
    /// when leaving and re-entering the picker.
    pub fn releaseOrder(self: *Model) void {
        self.freeze_order = false;
    }

    pub fn itemCount(self: *const Model) usize {
        if (self.snapshot.radio != .ready) return 1;
        // Switch + networks + hidden network + optional saved-networks row.
        var count: usize = 2 + self.snapshot.network_count;
        for (self.snapshot.items()) |network| if (network.saved and !network.in_range) {
            count += 1;
            break;
        };
        return count;
    }

    pub fn move(self: *Model, delta: i8) bool {
        const before = self.selected;
        if (delta < 0) self.selected -|= 1 else self.selected = @min(self.selected + 1, self.itemCount() -| 1);
        self.freeze_order = true;
        self.updateFocus();
        return before != self.selected;
    }

    pub fn queue(self: *Model, kind: CommandKind, network: ?Identity, value: bool) void {
        self.pending = .{
            .generation = self.snapshot.generation,
            .request_id = self.next_request_id,
            .kind = kind,
            .network = network,
            .value = value,
        };
        self.next_request_id +%= 1;
        if (self.next_request_id == 0) self.next_request_id = 1;
    }

    pub fn takeCommand(self: *Model) ?Command {
        const pending = self.pending;
        self.pending = null;
        return pending;
    }

    pub fn selectedNetwork(self: *const Model) ?Network {
        if (self.selected == 0 or self.selected > self.snapshot.network_count) return null;
        return self.snapshot.networks[self.selected - 1];
    }

    fn updateFocus(self: *Model) void {
        self.focused = if (self.selectedNetwork()) |network| network.id else null;
    }
};

fn stableOrder(previous: Snapshot, latest: Snapshot) Snapshot {
    var result = latest;
    result.network_count = 0;
    for (previous.items()) |old| {
        const index = latest.find(old.id) orelse continue;
        result.networks[result.network_count] = latest.networks[index];
        result.network_count += 1;
    }
    for (latest.items()) |network| {
        if (previous.find(network.id) != null) continue;
        result.networks[result.network_count] = network;
        result.network_count += 1;
    }
    return result;
}

pub fn stateDetail(state: NetworkState) []const u8 {
    return switch (state) {
        .available => "Available",
        .saved => "Saved",
        .connecting => "Connecting\xe2\x80\xa6",
        .validating => "Checking\xe2\x80\xa6",
        .connected => "Connected",
        .sign_in => "Sign-in required",
        .limited => "No internet",
        .reconnecting => "Reconnecting\xe2\x80\xa6",
        .auth_failed => "Password incorrect",
        .address_failed => "Couldn't get address",
        .out_of_range => "Out of range",
        .unsupported => "Not supported",
    };
}

fn parseEnum(comptime T: type, value: []const u8) !T {
    const info = @typeInfo(T).@"enum";
    inline for (info.field_names, info.field_values) |name, field_value| {
        if (std.mem.eql(u8, value, name)) return @fromBackingInt(@intCast(field_value));
    }
    return error.InvalidEnum;
}

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "1")) return true;
    if (std.mem.eql(u8, value, "0")) return false;
    return error.InvalidBoolean;
}

fn decodeHex(output: []u8, value: []const u8) ![]const u8 {
    if (value.len % 2 != 0 or value.len / 2 > output.len) return error.InvalidHex;
    for (0..value.len / 2) |index| output[index] = try std.fmt.parseInt(u8, value[index * 2 .. index * 2 + 2], 16);
    return output[0 .. value.len / 2];
}

fn fields(line: []const u8) std.mem.TokenIterator(u8, .scalar) {
    return std.mem.tokenizeScalar(u8, line, ' ');
}

pub fn parse(text: []const u8) !Snapshot {
    var snapshot = Snapshot{};
    var have_header = false;
    var complete = false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (!have_header) {
            var tokens = fields(line);
            if (!std.mem.eql(u8, tokens.next() orelse return error.MissingHeader, "snapshot")) return error.MissingHeader;
            while (tokens.next()) |field| {
                const equals = std.mem.indexOfScalar(u8, field, '=') orelse return error.InvalidField;
                const key = field[0..equals];
                const value = field[equals + 1 ..];
                if (std.mem.eql(u8, key, "generation")) snapshot.generation = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "revision")) snapshot.revision = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "radio")) snapshot.radio = try parseEnum(RadioState, value) else if (std.mem.eql(u8, key, "connectivity")) snapshot.connectivity = try parseEnum(Connectivity, value) else if (std.mem.eql(u8, key, "can_scan")) snapshot.can_scan = try parseBool(value) else return error.UnknownField;
            }
            have_header = true;
            continue;
        }
        if (std.mem.eql(u8, line, "end")) {
            complete = true;
            break;
        }
        if (snapshot.network_count >= max_networks) return error.TooManyNetworks;
        var tokens = fields(line);
        if (!std.mem.eql(u8, tokens.next() orelse return error.InvalidNetwork, "network")) return error.InvalidNetwork;
        var network = Network{};
        var have_id = false;
        var have_name = false;
        var name_buffer: [max_name_bytes]u8 = undefined;
        while (tokens.next()) |field| {
            const equals = std.mem.indexOfScalar(u8, field, '=') orelse return error.InvalidField;
            const key = field[0..equals];
            const value = field[equals + 1 ..];
            if (std.mem.eql(u8, key, "id")) {
                try network.id.set(value);
                have_id = true;
            } else if (std.mem.eql(u8, key, "name_hex")) {
                try network.name.setScanName(try decodeHex(&name_buffer, value));
                have_name = true;
            } else if (std.mem.eql(u8, key, "address_hex")) {
                try network.address.set(try decodeHex(&name_buffer, value));
            } else if (std.mem.eql(u8, key, "security")) network.security = try parseEnum(Security, value) else if (std.mem.eql(u8, key, "signal")) network.signal = try parseEnum(Signal, value) else if (std.mem.eql(u8, key, "state")) network.state = try parseEnum(NetworkState, value) else if (std.mem.eql(u8, key, "saved")) network.saved = try parseBool(value) else if (std.mem.eql(u8, key, "current")) network.current = try parseBool(value) else if (std.mem.eql(u8, key, "in_range")) network.in_range = try parseBool(value) else if (std.mem.eql(u8, key, "auto")) network.auto_connect = try parseBool(value) else if (std.mem.eql(u8, key, "private")) network.private_address = try parseBool(value) else return error.UnknownField;
        }
        if (!have_id or !have_name) return error.InvalidNetwork;
        if (snapshot.find(network.id) != null) return error.DuplicateIdentity;
        snapshot.networks[snapshot.network_count] = network;
        snapshot.network_count += 1;
    }
    if (!have_header or !complete) return error.IncompleteSnapshot;
    return snapshot;
}

test "snapshot parser preserves hostile names as distinct UTF-8 data" {
    const snapshot = try parse(
        "snapshot generation=7 revision=19 radio=ready connectivity=internet can_scan=1\n" ++
            "network id=home-secure name_hex=416c64657220486f757365 security=wpa2_personal signal=strong state=connected saved=1 current=1 in_range=1 auto=1 private=1\n" ++
            "network id=home-open name_hex=416c64657220486f757365 security=open signal=fair state=available saved=0 current=0 in_range=1 auto=0 private=1\n" ++
            "end\n",
    );
    try std.testing.expectEqual(@as(u32, 7), snapshot.generation);
    try std.testing.expectEqual(@as(u8, 2), snapshot.network_count);
    try std.testing.expectEqualStrings("Alder House", snapshot.networks[0].name.slice());
    try std.testing.expect(!Identity.eql(snapshot.networks[0].id, snapshot.networks[1].id));
}

test "malformed scan bytes have a stable lossless escaped display name" {
    const snapshot = try parse(
        "snapshot generation=1 revision=1 radio=ready connectivity=none can_scan=1\n" ++
            "network id=bad name_hex=66ff80 security=open signal=weak state=available saved=0 current=0 in_range=1 auto=0 private=1\n" ++
            "end\n",
    );
    try std.testing.expectEqualStrings("\\x66\\xff\\x80", snapshot.networks[0].name.slice());
}

test "model freezes row order during navigation then preserves focus after release" {
    var first = try parse(
        "snapshot generation=2 revision=1 radio=ready connectivity=none can_scan=1\n" ++
            "network id=one name_hex=4f6e65 security=wpa2_personal signal=fair state=saved saved=1 current=0 in_range=1 auto=1 private=1\n" ++
            "network id=two name_hex=54776f security=open signal=strong state=available saved=0 current=0 in_range=1 auto=0 private=1\n" ++
            "end\n",
    );
    var state = Model{};
    try std.testing.expect(state.update(first));
    _ = state.move(1);
    _ = state.move(1);
    try std.testing.expectEqualStrings("two", state.focused.?.slice());
    first.revision = 2;
    const swap = first.networks[0];
    first.networks[0] = first.networks[1];
    first.networks[1] = swap;
    try std.testing.expect(state.update(first));
    try std.testing.expectEqual(@as(usize, 2), state.selected);
    try std.testing.expectEqualStrings("two", state.focused.?.slice());
    state.releaseOrder();
    first.revision = 3;
    try std.testing.expect(state.update(first));
    try std.testing.expectEqual(@as(usize, 1), state.selected);
    try std.testing.expectEqualStrings("two", state.focused.?.slice());
}

test "commands bind generation and stable request id" {
    var state = Model{};
    state.snapshot.generation = 44;
    state.queue(.scan, null, false);
    const command = state.takeCommand().?;
    try std.testing.expectEqual(@as(u32, 44), command.generation);
    try std.testing.expectEqual(@as(u32, 1), command.request_id);
    try std.testing.expectEqual(CommandKind.scan, command.kind);
}
