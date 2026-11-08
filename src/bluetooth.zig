// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

/// Product-facing state. These values deliberately do not mirror BlueZ's
/// properties one-for-one: the shell needs to distinguish a usable audio route
/// from a device that merely has a Bluetooth link.
pub const RadioState = enum {
    unavailable,
    off,
    starting,
    ready,
    stopping,
    failed,
};

pub const DiscoveryState = enum { idle, scanning_classic, scanning_low_energy, failed };
/// Backend-only network state used to coordinate the shared XR829 radio.
/// The shell continues to show one device search while execution yields.
pub const NetworkActivity = enum { inactive, associated, changing };
pub const ScanExecution = enum { stopped, classic, low_energy };
pub const CoexistencePlan = struct {
    execution: ScanExecution,
};
pub const DeviceKind = enum { audio, controller, other };

pub const DeviceState = enum {
    nearby,
    saved,
    pairing,
    connecting,
    connected,
    preparing_audio,
    ready,
    disconnecting,
    failed,
};

pub const Device = struct {
    name: []const u8,
    address: []const u8,
    kind: DeviceKind,
    state: DeviceState,

    pub fn label(self: Device) []const u8 {
        return if (self.name.len == 0) self.address else self.name;
    }

    pub fn detail(self: Device) []const u8 {
        return switch (self.state) {
            .nearby => switch (self.kind) {
                .audio => "Nearby audio device",
                .controller => "Nearby controller",
                .other => "Nearby device",
            },
            .saved => "Saved",
            .pairing => "Pairing…",
            .connecting => "Connecting…",
            .connected => if (self.kind == .audio) "Connected; preparing audio…" else "Connected",
            .preparing_audio => "Preparing audio…",
            .ready => if (self.kind == .audio) "Audio ready" else "Connected",
            .disconnecting => "Disconnecting…",
            .failed => "Connection failed",
        };
    }

    pub fn canForget(self: Device) bool {
        return switch (self.state) {
            .saved, .connecting, .connected, .preparing_audio, .ready, .disconnecting, .failed => true,
            else => false,
        };
    }
};

pub const Operation = enum { none, radio_change, discovery, pairing, connection, disconnection };
pub const Intent = enum { none, turn_on, turn_off, scan, stop_scan, pair, connect, disconnect, retry, cancel, forget };

pub fn primaryIntent(device: Device) Intent {
    return switch (device.state) {
        .nearby => .pair,
        .saved => .connect,
        .pairing, .connecting => .cancel,
        .connected, .preparing_audio, .ready => .disconnect,
        .disconnecting => .none,
        .failed => .retry,
    };
}

pub fn cancellationIntent(operation: Operation) Intent {
    return switch (operation) {
        .none => .none,
        .discovery => .stop_scan,
        .radio_change, .pairing, .connection, .disconnection => .cancel,
    };
}

/// Stable grouping for a handheld list: active devices first, then saved
/// devices, then discoveries. Sorting within a group remains alphabetical.
pub fn groupRank(device: Device) u8 {
    return switch (device.state) {
        .ready, .connected, .preparing_audio, .connecting, .disconnecting => 0,
        .saved, .failed => 1,
        .pairing => 2,
        .nearby => 3,
    };
}

pub fn radioSummary(radio: RadioState, discovery: DiscoveryState) []const u8 {
    return switch (radio) {
        .unavailable => "Bluetooth unavailable",
        .off => "Bluetooth off",
        .starting => "Turning Bluetooth on…",
        .stopping => "Turning Bluetooth off…",
        .failed => "Bluetooth could not start",
        .ready => switch (discovery) {
            .idle => "Bluetooth on",
            .scanning_classic, .scanning_low_energy => "Looking for devices…",
            .failed => "Device search failed",
        },
    };
}

/// Discovery yields to Wi-Fi association, roaming, validation or captive
/// sign-in. Wi-Fi power save stays at the product baseline: device trials
/// showed that changing it during discovery delayed reassociation.
pub fn coexistencePlan(discovery: DiscoveryState, network: NetworkActivity) CoexistencePlan {
    if (network == .changing) return .{ .execution = .stopped };
    return switch (discovery) {
        .idle, .failed => .{ .execution = .stopped },
        .scanning_classic => .{ .execution = .classic },
        .scanning_low_energy => .{ .execution = .low_energy },
    };
}

test "device actions stay reversible while work is in progress" {
    const nearby = Device{ .name = "Headphones", .address = "00:11:22:33:44:55", .kind = .audio, .state = .nearby };
    try std.testing.expectEqual(Intent.pair, primaryIntent(nearby));
    try std.testing.expectEqual(Intent.cancel, primaryIntent(.{ .name = nearby.name, .address = nearby.address, .kind = .audio, .state = .pairing }));
    try std.testing.expectEqual(Intent.cancel, primaryIntent(.{ .name = nearby.name, .address = nearby.address, .kind = .audio, .state = .connecting }));
    try std.testing.expectEqual(Intent.disconnect, primaryIntent(.{ .name = nearby.name, .address = nearby.address, .kind = .audio, .state = .ready }));
    try std.testing.expectEqual(Intent.stop_scan, cancellationIntent(.discovery));
}

test "audio readiness is distinct from a Bluetooth connection" {
    const connected = Device{ .name = "Headphones", .address = "00:11:22:33:44:55", .kind = .audio, .state = .connected };
    const ready = Device{ .name = connected.name, .address = connected.address, .kind = .audio, .state = .ready };
    try std.testing.expectEqualStrings("Connected; preparing audio…", connected.detail());
    try std.testing.expectEqualStrings("Audio ready", ready.detail());
}

test "saved devices remain ahead of new discoveries" {
    const saved = Device{ .name = "Controller", .address = "AA:BB:CC:DD:EE:FF", .kind = .controller, .state = .saved };
    const nearby = Device{ .name = "", .address = "00:11:22:33:44:55", .kind = .other, .state = .nearby };
    try std.testing.expect(groupRank(saved) < groupRank(nearby));
    try std.testing.expectEqualStrings(nearby.address, nearby.label());
}

test "radio status says what the user can observe" {
    try std.testing.expectEqualStrings("Bluetooth off", radioSummary(.off, .idle));
    try std.testing.expectEqualStrings("Looking for devices…", radioSummary(.ready, .scanning_classic));
    try std.testing.expectEqualStrings("Looking for devices…", radioSummary(.ready, .scanning_low_energy));
    try std.testing.expectEqualStrings("Device search failed", radioSummary(.ready, .failed));
}

test "discovery yields to Wi-Fi state changes without exposing transport" {
    const classic = coexistencePlan(.scanning_classic, .changing);
    const low_energy = coexistencePlan(.scanning_low_energy, .changing);
    try std.testing.expectEqual(ScanExecution.stopped, classic.execution);
    try std.testing.expectEqual(ScanExecution.stopped, low_energy.execution);
    try std.testing.expectEqualStrings(
        radioSummary(.ready, .scanning_classic),
        radioSummary(.ready, .scanning_low_energy),
    );
}

test "stable links keep discovery transport internal without changing Wi-Fi policy" {
    const classic = coexistencePlan(.scanning_classic, .associated);
    const low_energy = coexistencePlan(.scanning_low_energy, .associated);
    try std.testing.expectEqual(ScanExecution.classic, classic.execution);
    try std.testing.expectEqual(ScanExecution.low_energy, low_energy.execution);
    try std.testing.expectEqual(ScanExecution.low_energy, coexistencePlan(.scanning_low_energy, .inactive).execution);
    try std.testing.expectEqual(ScanExecution.stopped, coexistencePlan(.idle, .associated).execution);
}
