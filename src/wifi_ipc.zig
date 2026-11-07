// SPDX-License-Identifier: GPL-2.0-only
//! Versioned, packet-oriented contract between the shell and Wi-Fi authority.
//! One SOCK_SEQPACKET packet is one complete command, snapshot, or result, so
//! a slow or restarted authority cannot leave the shell parsing half a state.
const std = @import("std");
const wifi = @import("wifi.zig");
const flow = @import("wifi_flow.zig");

pub const protocol_version = 1;
pub const max_packet = 16 * 1024;

pub const ResultStatus = enum { accepted, stale, rejected };

pub const Result = struct {
    generation: u32,
    request_id: u32,
    status: ResultStatus,
    reason: wifi.Text = .{},
};

pub const Event = union(enum) {
    snapshot: wifi.Snapshot,
    result: Result,
};

fn append(buffer: []u8, cursor: *usize, value: []const u8) !void {
    if (cursor.* + value.len > buffer.len) return error.PacketTooLarge;
    @memcpy(buffer[cursor.*..][0..value.len], value);
    cursor.* += value.len;
}

fn appendFmt(buffer: []u8, cursor: *usize, comptime format: []const u8, args: anytype) !void {
    const value = try std.fmt.bufPrint(buffer[cursor.*..], format, args);
    cursor.* += value.len;
}

fn appendHex(buffer: []u8, cursor: *usize, value: []const u8) !void {
    const alphabet = "0123456789abcdef";
    if (cursor.* + value.len * 2 > buffer.len) return error.PacketTooLarge;
    for (value) |byte| {
        buffer[cursor.*] = alphabet[byte >> 4];
        buffer[cursor.* + 1] = alphabet[byte & 0xf];
        cursor.* += 2;
    }
}

pub fn encodeRequest(buffer: []u8, request: *const flow.Request) ![]const u8 {
    var cursor: usize = 0;
    try appendFmt(buffer, &cursor, "command version={d} generation={d} request={d} kind={s}", .{
        protocol_version,
        request.command.generation,
        request.command.request_id,
        @tagName(request.command.kind),
    });
    if (request.command.network) |network| try appendFmt(buffer, &cursor, " network={s}", .{network.slice()});
    try appendFmt(buffer, &cursor, " value={d} security={s} ssid_hex=", .{
        @intFromBool(request.command.value),
        @tagName(request.security),
    });
    try appendHex(buffer, &cursor, request.ssid[0..request.ssid_len]);
    try append(buffer, &cursor, " credential_hex=");
    try appendHex(buffer, &cursor, request.credentialSlice());
    try append(buffer, &cursor, "\n");
    return buffer[0..cursor];
}

fn decodeHex(output: []u8, value: []const u8) ![]const u8 {
    if (value.len % 2 != 0 or value.len / 2 > output.len) return error.InvalidHex;
    for (0..value.len / 2) |index| output[index] = try std.fmt.parseInt(u8, value[index * 2 .. index * 2 + 2], 16);
    return output[0 .. value.len / 2];
}

fn parseResult(packet: []const u8) !Result {
    var tokens = std.mem.tokenizeAny(u8, packet, " \n");
    if (!std.mem.eql(u8, tokens.next() orelse return error.InvalidResult, "result")) return error.InvalidResult;
    var generation: ?u32 = null;
    var request_id: ?u32 = null;
    var status: ?ResultStatus = null;
    var reason = wifi.Text{};
    while (tokens.next()) |field| {
        const equals = std.mem.indexOfScalar(u8, field, '=') orelse return error.InvalidResult;
        const key = field[0..equals];
        const value = field[equals + 1 ..];
        if (std.mem.eql(u8, key, "generation")) generation = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "request")) request_id = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "status")) {
            status = if (std.mem.eql(u8, value, "accepted")) .accepted else if (std.mem.eql(u8, value, "stale")) .stale else if (std.mem.eql(u8, value, "rejected")) .rejected else return error.InvalidResult;
        } else if (std.mem.eql(u8, key, "reason_hex")) {
            var decoded: [wifi.max_name_bytes]u8 = undefined;
            try reason.set(try decodeHex(&decoded, value));
        } else return error.InvalidResult;
    }
    return .{
        .generation = generation orelse return error.InvalidResult,
        .request_id = request_id orelse return error.InvalidResult,
        .status = status orelse return error.InvalidResult,
        .reason = reason,
    };
}

pub fn parseEvent(packet: []const u8) !Event {
    if (std.mem.startsWith(u8, packet, "snapshot ")) return .{ .snapshot = try wifi.parse(packet) };
    if (std.mem.startsWith(u8, packet, "result ")) return .{ .result = try parseResult(packet) };
    return error.UnknownPacket;
}

/// Linux transport. Production connects this descriptor to the shell's input
/// poll set; receive is called only after readiness, never on the render path.
pub const Client = struct {
    fd: std.os.linux.fd_t,

    pub fn connect(path: []const u8) !Client {
        if (path.len == 0 or path.len >= @sizeOf(@FieldType(std.os.linux.sockaddr.un, "path"))) return error.InvalidSocketPath;
        const raw = std.os.linux.socket(std.os.linux.AF.UNIX, std.os.linux.SOCK.SEQPACKET | std.os.linux.SOCK.CLOEXEC, 0);
        if (std.posix.errno(raw) != .SUCCESS) return error.SocketFailed;
        const fd: std.os.linux.fd_t = @intCast(raw);
        errdefer _ = std.os.linux.close(fd);
        var address = std.os.linux.sockaddr.un{ .path = @splat(0) };
        @memcpy(address.path[0..path.len], path);
        const length: std.os.linux.socklen_t = @intCast(@sizeOf(std.os.linux.sa_family_t) + path.len + 1);
        const rc = std.os.linux.connect(fd, &address, length);
        if (std.posix.errno(rc) != .SUCCESS) return error.ConnectFailed;
        return .{ .fd = fd };
    }

    pub fn close(self: Client) void {
        _ = std.os.linux.close(self.fd);
    }

    pub fn send(self: Client, request: *flow.Request) !void {
        var packet: [max_packet]u8 = undefined;
        defer std.crypto.secureZero(u8, &packet);
        defer request.wipe();
        const bytes = try encodeRequest(&packet, request);
        const rc = std.os.linux.write(self.fd, bytes.ptr, bytes.len);
        if (std.posix.errno(rc) != .SUCCESS) return error.SendFailed;
        if (rc != bytes.len) return error.ShortPacket;
    }

    pub fn receive(self: Client, buffer: []u8) !Event {
        const rc = std.os.linux.read(self.fd, buffer.ptr, buffer.len);
        if (std.posix.errno(rc) != .SUCCESS) return error.ReceiveFailed;
        if (rc == 0) return error.Closed;
        if (rc == buffer.len) return error.PacketTooLarge;
        return parseEvent(buffer[0..rc]);
    }
};

fn socketPair() ![2]std.os.linux.fd_t {
    var fds: [2]std.os.linux.fd_t = undefined;
    const rc = std.os.linux.socketpair(std.os.linux.AF.UNIX, std.os.linux.SOCK.SEQPACKET | std.os.linux.SOCK.CLOEXEC, 0, &fds);
    if (std.posix.errno(rc) != .SUCCESS) return error.SocketPairFailed;
    return fds;
}

test "request is one packet and sending scrubs caller credential" {
    const fds = try socketPair();
    defer _ = std.os.linux.close(fds[0]);
    defer _ = std.os.linux.close(fds[1]);
    var request = flow.Request{
        .command = .{ .generation = 42, .request_id = 7, .kind = .connect },
        .security = .wpa2_personal,
    };
    @memcpy(request.credential[0..6], "secret");
    request.credential_len = 6;
    try (Client{ .fd = fds[0] }).send(&request);
    try std.testing.expectEqual(@as(u8, 0), request.credential_len);
    for (request.credential) |byte| try std.testing.expectEqual(@as(u8, 0), byte);

    var packet: [max_packet]u8 = undefined;
    const size = std.os.linux.read(fds[1], &packet, packet.len);
    try std.testing.expectEqual(std.posix.E.SUCCESS, std.posix.errno(size));
    try std.testing.expect(std.mem.indexOf(u8, packet[0..size], "generation=42 request=7") != null);
    try std.testing.expect(std.mem.indexOf(u8, packet[0..size], "credential_hex=736563726574") != null);
}

test "asynchronous snapshots and stale results remain distinct packets" {
    const fds = try socketPair();
    defer _ = std.os.linux.close(fds[0]);
    defer _ = std.os.linux.close(fds[1]);
    const snapshot = "snapshot generation=9 revision=3 radio=ready connectivity=internet can_scan=1\nend\n";
    const stale = "result generation=10 request=12 status=stale reason_hex=72656672657368\n";
    try std.testing.expectEqual(snapshot.len, std.os.linux.write(fds[1], snapshot.ptr, snapshot.len));
    try std.testing.expectEqual(stale.len, std.os.linux.write(fds[1], stale.ptr, stale.len));
    var packet: [max_packet]u8 = undefined;
    const client = Client{ .fd = fds[0] };
    const first = try client.receive(&packet);
    try std.testing.expectEqual(@as(u32, 9), first.snapshot.generation);
    const second = try client.receive(&packet);
    try std.testing.expectEqual(ResultStatus.stale, second.result.status);
    try std.testing.expectEqualStrings("refresh", second.result.reason.slice());
}
