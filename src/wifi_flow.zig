// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const input = @import("input.zig");
const wifi = @import("wifi.zig");

pub const Page = enum { list, details, password, open_confirm, hidden_name, hidden_security, info, forget_confirm };
pub const SecurityChoice = enum { open, wpa2_personal };

pub const Field = struct {
    bytes: [96]u8 = @splat(0),
    len: u8 = 0,
    selected: u8 = 10,
    uppercase: bool = false,
    symbols: bool = false,

    pub fn slice(self: *const Field) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn wipe(self: *Field) void {
        std.crypto.secureZero(u8, &self.bytes);
        self.len = 0;
        self.selected = 10;
        self.uppercase = false;
        self.symbols = false;
    }

    pub fn move(self: *Field, action: input.Action) bool {
        const before = self.selected;
        switch (action) {
            .left => self.selected = if (self.selected % 10 == 0) self.selected else self.selected - 1,
            .right => {
                if (self.selected % 10 != 9) self.selected = @min(39, self.selected + 1);
            },
            .up => self.selected -|= 10,
            .down => self.selected = @min(39, self.selected + 10),
            else => return false,
        }
        return before != self.selected;
    }

    pub fn activate(self: *Field) enum { changed, submit, unchanged } {
        if (self.selected < 36) {
            if (self.len == self.bytes.len) return .unchanged;
            const lower = "1234567890qwertyuiopasdfghjklzxcvbnm";
            const upper = "1234567890QWERTYUIOPASDFGHJKLZXCVBNM";
            const symbols = "1234567890!@#$%^&*()[]{}<>?+-=_/:;,.~`";
            const keys = if (self.symbols) symbols else if (self.uppercase) upper else lower;
            self.bytes[self.len] = keys[self.selected];
            self.len += 1;
            return .changed;
        }
        switch (self.selected) {
            36 => self.uppercase = !self.uppercase,
            37 => self.symbols = !self.symbols,
            38 => {
                if (self.len == 0) return .unchanged;
                self.len -= 1;
                self.bytes[self.len] = 0;
            },
            else => return .submit,
        }
        return .changed;
    }
};

pub const Request = struct {
    command: wifi.Command,
    ssid: [96]u8 = @splat(0),
    ssid_len: u8 = 0,
    credential: [96]u8 = @splat(0),
    credential_len: u8 = 0,
    security: wifi.Security = .unsupported,

    pub fn credentialSlice(self: *const Request) []const u8 {
        return self.credential[0..self.credential_len];
    }

    pub fn wipe(self: *Request) void {
        std.crypto.secureZero(u8, &self.credential);
        self.credential_len = 0;
        std.crypto.secureZero(u8, &self.ssid);
        self.ssid_len = 0;
    }
};

pub const Model = struct {
    wifi_state: wifi.Model = .{},
    page: Page = .list,
    active: ?wifi.Identity = null,
    detail_selected: usize = 0,
    confirm_selected: usize = 0,
    field: Field = .{},
    hidden_name: [96]u8 = @splat(0),
    hidden_name_len: u8 = 0,
    hidden_security: SecurityChoice = .wpa2_personal,
    pending: ?Request = null,
    retry_credential: [96]u8 = @splat(0),
    retry_credential_len: u8 = 0,
    show_password: bool = false,

    pub fn update(self: *Model, snapshot: wifi.Snapshot) bool {
        if (self.wifi_state.snapshot.generation != 0 and snapshot.generation != self.wifi_state.snapshot.generation) {
            self.field.wipe();
            self.clearRetryCredential();
            self.clearHiddenName();
            self.clearPending();
            self.show_password = false;
        }
        const changed = self.wifi_state.update(snapshot);
        if (self.active) |identity| {
            if (snapshot.find(identity)) |index| {
                if (snapshot.networks[index].state == .connected) self.clearRetryCredential();
            } else if (self.page != .password and self.page != .open_confirm) {
                self.page = .list;
                self.active = null;
                self.detail_selected = 0;
            }
        }
        return changed;
    }

    pub fn activeNetwork(self: *const Model) ?*const wifi.Network {
        const identity = self.active orelse return null;
        const index = self.wifi_state.snapshot.find(identity) orelse return null;
        return &self.wifi_state.snapshot.networks[index];
    }

    pub fn apply(self: *Model, action: input.Action) bool {
        return switch (self.page) {
            .list => self.applyList(action),
            .details => self.applyDetails(action),
            .password, .hidden_name => self.applyField(action),
            .hidden_security => self.applyHiddenSecurity(action),
            .open_confirm, .forget_confirm => self.applyConfirmation(action),
            .info => if (action == .back) blk: {
                self.page = .details;
                break :blk true;
            } else false,
        };
    }

    fn applyList(self: *Model, action: input.Action) bool {
        switch (action) {
            .up => return self.wifi_state.move(-1),
            .down => return self.wifi_state.move(1),
            .filter => {
                if (!self.wifi_state.snapshot.can_scan) return false;
                self.queueSimple(.scan, null, false);
                return true;
            },
            .select => {
                if (self.wifi_state.selected == 0) {
                    const enabled = switch (self.wifi_state.snapshot.radio) {
                        .off, .failed => true,
                        .starting, .ready => false,
                        .unavailable, .stopping => return false,
                    };
                    self.queueSimple(.set_enabled, null, enabled);
                    return true;
                }
                if (self.wifi_state.selectedNetwork()) |network| {
                    self.active = network.id;
                    switch (network.state) {
                        .connected, .sign_in, .limited, .connecting, .validating, .reconnecting, .auth_failed, .address_failed, .unsupported => self.page = .details,
                        .saved, .out_of_range => self.queueSimple(.connect, network.id, false),
                        .available => {
                            if (network.security == .open) {
                                self.confirm_selected = 0;
                                self.page = .open_confirm;
                            } else if (network.security == .wpa2_personal) {
                                self.field.wipe();
                                self.page = .password;
                            } else self.page = .details;
                        },
                    }
                    return true;
                }
                if (self.wifi_state.selected == self.wifi_state.snapshot.network_count + 1) {
                    self.field.wipe();
                    self.page = .hidden_name;
                    return true;
                }
            },
            .back => return false,
            else => {},
        }
        return false;
    }

    fn applyDetails(self: *Model, action: input.Action) bool {
        const network = self.activeNetwork() orelse return false;
        switch (action) {
            .up => self.detail_selected -|= 1,
            .down => self.detail_selected = @min(4, self.detail_selected + 1),
            .back => {
                self.page = .list;
                self.detail_selected = 0;
            },
            .select => switch (self.detail_selected) {
                0 => switch (network.state) {
                    .sign_in => self.queueSimple(.open_captive, network.id, false),
                    .limited => self.queueSimple(.recheck, network.id, false),
                    .connected => self.queueSimple(.disconnect, network.id, false),
                    .connecting, .validating, .reconnecting => self.queueSimple(.cancel, network.id, false),
                    .auth_failed => {
                        self.field.wipe();
                        @memcpy(self.field.bytes[0..self.retry_credential_len], self.retry_credential[0..self.retry_credential_len]);
                        self.field.len = self.retry_credential_len;
                        self.page = .password;
                    },
                    else => self.queueSimple(.connect, network.id, false),
                },
                1 => self.queueSimple(.set_auto_connect, network.id, !network.auto_connect),
                2 => self.queueSimple(.set_private_address, network.id, !network.private_address),
                3 => self.page = .info,
                4 => {
                    self.confirm_selected = 0;
                    self.page = .forget_confirm;
                },
                else => unreachable,
            },
            else => return false,
        }
        return true;
    }

    fn applyField(self: *Model, action: input.Action) bool {
        switch (action) {
            .up, .down, .left, .right => return self.field.move(action),
            .view => {
                self.show_password = !self.show_password;
                return true;
            },
            .filter => {
                self.field.symbols = !self.field.symbols;
                return true;
            },
            .back => {
                self.field.wipe();
                self.clearRetryCredential();
                self.clearHiddenName();
                self.show_password = false;
                self.page = .list;
                return true;
            },
            .select => switch (self.field.activate()) {
                .unchanged => return false,
                .changed => return true,
                .submit => {
                    if (self.field.len == 0) return false;
                    if (self.page == .hidden_name) {
                        @memcpy(self.hidden_name[0..self.field.len], self.field.slice());
                        self.hidden_name_len = self.field.len;
                        self.field.wipe();
                        self.page = .hidden_security;
                    } else if (self.active) |identity| {
                        self.queueJoin(identity, .wpa2_personal, &.{}, self.field.slice());
                    } else {
                        self.queueJoin(null, .wpa2_personal, self.hidden_name[0..self.hidden_name_len], self.field.slice());
                    }
                    return true;
                },
            },
            else => return false,
        }
    }

    fn applyHiddenSecurity(self: *Model, action: input.Action) bool {
        switch (action) {
            .up, .down, .left, .right => self.hidden_security = if (self.hidden_security == .open) .wpa2_personal else .open,
            .back => {
                self.field.wipe();
                self.page = .hidden_name;
            },
            .select => if (self.hidden_security == .open) {
                self.queueJoin(null, .open, self.hidden_name[0..self.hidden_name_len], &.{});
            } else {
                self.field.wipe();
                self.page = .password;
            },
            else => return false,
        }
        return true;
    }

    fn applyConfirmation(self: *Model, action: input.Action) bool {
        switch (action) {
            .up, .down, .left, .right => self.confirm_selected = 1 - self.confirm_selected,
            .back => {
                self.page = if (self.page == .forget_confirm) .details else .list;
                self.confirm_selected = 0;
            },
            .select => {
                if (self.confirm_selected == 0) {
                    self.page = if (self.page == .forget_confirm) .details else .list;
                } else if (self.page == .forget_confirm) {
                    self.queueSimple(.forget, self.active, false);
                    self.page = .list;
                    self.active = null;
                } else {
                    self.queueJoin(self.active, .open, &.{}, &.{});
                }
                self.confirm_selected = 0;
            },
            else => return false,
        }
        return true;
    }

    fn queueSimple(self: *Model, kind: wifi.CommandKind, network: ?wifi.Identity, value: bool) void {
        self.clearPending();
        self.wifi_state.queue(kind, network, value);
        self.pending = .{ .command = self.wifi_state.takeCommand().? };
    }

    fn queueJoin(self: *Model, identity: ?wifi.Identity, security: wifi.Security, ssid: []const u8, credential: []const u8) void {
        self.clearPending();
        self.wifi_state.queue(.connect, identity, false);
        var request = Request{ .command = self.wifi_state.takeCommand().?, .security = security };
        @memcpy(request.ssid[0..ssid.len], ssid);
        request.ssid_len = @intCast(ssid.len);
        @memcpy(request.credential[0..credential.len], credential);
        request.credential_len = @intCast(credential.len);
        if (security == .wpa2_personal) {
            self.clearRetryCredential();
            @memcpy(self.retry_credential[0..credential.len], credential);
            self.retry_credential_len = @intCast(credential.len);
        }
        self.pending = request;
        self.field.wipe();
        self.show_password = false;
        self.clearHiddenName();
        self.page = .list;
    }

    fn clearHiddenName(self: *Model) void {
        std.crypto.secureZero(u8, &self.hidden_name);
        self.hidden_name_len = 0;
    }

    fn clearRetryCredential(self: *Model) void {
        std.crypto.secureZero(u8, &self.retry_credential);
        self.retry_credential_len = 0;
    }

    fn clearPending(self: *Model) void {
        if (self.pending) |*request| request.wipe();
        self.pending = null;
    }

    pub fn takeRequest(self: *Model) ?Request {
        const pending = self.pending orelse return null;
        self.pending.?.wipe();
        self.pending = null;
        return pending;
    }
};

fn sample() !wifi.Snapshot {
    return wifi.parse(
        "snapshot generation=8 revision=1 radio=ready connectivity=none can_scan=1\n" ++
            "network id=saved name_hex=5361766564 security=wpa2_personal signal=good state=saved saved=1 current=0 in_range=1 auto=1 private=1\n" ++
            "network id=new name_hex=4e6577 security=wpa2_personal signal=strong state=available saved=0 current=0 in_range=1 auto=0 private=1\n" ++
            "network id=open name_hex=4f70656e security=open signal=fair state=available saved=0 current=0 in_range=1 auto=0 private=1\n" ++
            "end\n",
    );
}

test "saved joins immediately while secured and open networks use safe flows" {
    var state = Model{};
    _ = state.update(try sample());
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(wifi.CommandKind.connect, state.takeRequest().?.command.kind);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.password, state.page);
    _ = state.apply(.back);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.open_confirm, state.page);
}

test "password is generation-bound and wiped after submission" {
    var state = Model{};
    _ = state.update(try sample());
    _ = state.apply(.down);
    _ = state.apply(.down);
    _ = state.apply(.select);
    state.field.selected = 10; // q
    _ = state.apply(.select);
    state.field.selected = 39; // Go
    _ = state.apply(.select);
    const request = state.takeRequest().?;
    try std.testing.expectEqual(@as(u32, 8), request.command.generation);
    try std.testing.expectEqualStrings("q", request.credentialSlice());
    try std.testing.expectEqual(@as(u8, 0), state.field.len);
    for (state.field.bytes) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "details actions are explicit and forget is confirmed" {
    var snapshot = try sample();
    snapshot.networks[0].current = true;
    snapshot.networks[0].state = .connected;
    var state = Model{};
    _ = state.update(snapshot);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.details, state.page);
    state.detail_selected = 2;
    _ = state.apply(.select);
    const private = state.takeRequest().?;
    try std.testing.expectEqual(wifi.CommandKind.set_private_address, private.command.kind);
    try std.testing.expect(!private.command.value);
    state.detail_selected = 4;
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.forget_confirm, state.page);
    _ = state.apply(.down);
    _ = state.apply(.select);
    try std.testing.expectEqual(wifi.CommandKind.forget, state.takeRequest().?.command.kind);
}

test "hidden WPA2 join carries name and credential without a fake identity" {
    var state = Model{};
    _ = state.update(try sample());
    state.wifi_state.selected = state.wifi_state.snapshot.network_count + 1;
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.hidden_name, state.page);
    state.field.bytes[0] = 'x';
    state.field.len = 1;
    state.field.selected = 39;
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.hidden_security, state.page);
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.password, state.page);
    state.field.bytes[0] = 'p';
    state.field.len = 1;
    state.field.selected = 39;
    _ = state.apply(.select);
    const request = state.takeRequest().?;
    try std.testing.expect(request.command.network == null);
    try std.testing.expectEqualStrings("x", request.ssid[0..request.ssid_len]);
    try std.testing.expectEqualStrings("p", request.credentialSlice());
}

test "recoverable authentication failure restores then securely clears credential" {
    var state = Model{};
    var snapshot = try sample();
    _ = state.update(snapshot);
    state.wifi_state.selected = 2;
    _ = state.apply(.select);
    state.field.bytes[0] = 'p';
    state.field.len = 1;
    state.field.selected = 39;
    _ = state.apply(.select);
    var request = state.takeRequest().?;
    request.wipe();

    snapshot.revision = 2;
    snapshot.networks[1].state = .auth_failed;
    _ = state.update(snapshot);
    state.page = .details;
    state.detail_selected = 0;
    _ = state.apply(.select);
    try std.testing.expectEqual(Page.password, state.page);
    try std.testing.expectEqualStrings("p", state.field.slice());
    _ = state.apply(.back);
    try std.testing.expectEqual(@as(u8, 0), state.retry_credential_len);
    for (state.retry_credential) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "authority generation change clears every transient credential copy" {
    var state = Model{};
    var snapshot = try sample();
    _ = state.update(snapshot);
    state.wifi_state.selected = 2;
    _ = state.apply(.select);
    state.field.bytes[0] = 'p';
    state.field.len = 1;
    state.field.selected = 39;
    _ = state.apply(.select);
    try std.testing.expect(state.pending != null);
    snapshot.generation += 1;
    snapshot.revision = 1;
    _ = state.update(snapshot);
    try std.testing.expect(state.pending == null);
    try std.testing.expectEqual(@as(u8, 0), state.retry_credential_len);
    for (state.retry_credential) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}
