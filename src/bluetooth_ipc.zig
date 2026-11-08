// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const bluetooth = @import("bluetooth.zig");
pub const protocol_version = 1;
pub const max_packet = 16 * 1024;
pub const ResultStatus = enum { accepted, stale, rejected };
pub const Result = struct { generation: u32, request_id: u32, status: ResultStatus, reason: bluetooth.Text = .{} };
pub const Event = union(enum) { snapshot: bluetooth.Snapshot, result: Result };
fn appendFmt(buffer: []u8, cursor: *usize, comptime format: []const u8, args: anytype) !void {
    const value = try std.fmt.bufPrint(buffer[cursor.*..], format, args);
    cursor.* += value.len;
}
pub fn encodeCommand(buffer: []u8, command: *bluetooth.Command) ![]const u8 {
    defer command.wipe();
    var cursor: usize = 0;
    try appendFmt(buffer, &cursor, "command version={d} generation={d} request={d} kind={s}", .{ protocol_version, command.generation, command.request_id, @tagName(command.kind) });
    if (command.device) |id| try appendFmt(buffer, &cursor, " device={s}", .{id.slice()});
    try appendFmt(buffer, &cursor, " value={d}", .{@intFromBool(command.value)});
    if (command.secret_len != 0) try appendFmt(buffer, &cursor, " secret={s}", .{command.secret[0..command.secret_len]});
    if (cursor == buffer.len) return error.PacketTooLarge;
    buffer[cursor] = '\n';
    return buffer[0 .. cursor + 1];
}
fn decodeHex(output: []u8, value: []const u8) ![]const u8 {
    if (value.len % 2 != 0 or value.len / 2 > output.len) return error.InvalidHex;
    for (0..value.len / 2) |index| output[index] = try std.fmt.parseInt(u8, value[index * 2 .. index * 2 + 2], 16);
    return output[0 .. value.len / 2];
}
fn parseResult(packet: []const u8) !Result {
    var generation: ?u32 = null;
    var request: ?u32 = null;
    var status: ?ResultStatus = null;
    var reason: bluetooth.Text = .{};
    var tokens = std.mem.tokenizeAny(u8, packet, " \n");
    if (!std.mem.eql(u8, tokens.next() orelse return error.InvalidResult, "result")) return error.InvalidResult;
    while (tokens.next()) |token| {
        const equals = std.mem.indexOfScalar(u8, token, '=') orelse return error.InvalidResult;
        const key = token[0..equals];
        const value = token[equals + 1 ..];
        if (std.mem.eql(u8, key, "generation")) generation = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "request")) request = try std.fmt.parseInt(u32, value, 10) else if (std.mem.eql(u8, key, "status")) status = if (std.mem.eql(u8, value, "accepted")) .accepted else if (std.mem.eql(u8, value, "stale")) .stale else if (std.mem.eql(u8, value, "rejected")) .rejected else return error.InvalidResult else if (std.mem.eql(u8, key, "reason_hex")) {
            var decoded: [bluetooth.max_name_bytes]u8 = undefined;
            try reason.set(try decodeHex(&decoded, value));
        } else return error.InvalidResult;
    }
    return .{ .generation = generation orelse return error.InvalidResult, .request_id = request orelse return error.InvalidResult, .status = status orelse return error.InvalidResult, .reason = reason };
}
pub fn parseEvent(packet: []const u8) !Event {
    if (std.mem.startsWith(u8, packet, "snapshot ")) return .{ .snapshot = try bluetooth.parse(packet) };
    if (std.mem.startsWith(u8, packet, "result ")) return .{ .result = try parseResult(packet) };
    return error.UnknownPacket;
}
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
        if (std.posix.errno(std.os.linux.connect(fd, &address, length)) != .SUCCESS) return error.ConnectFailed;
        return .{ .fd = fd };
    }
    pub fn close(self: Client) void {
        _ = std.os.linux.close(self.fd);
    }
    pub fn send(self: Client, command: *bluetooth.Command) !void {
        var packet: [max_packet]u8 = undefined;
        defer std.crypto.secureZero(u8, &packet);
        const bytes = try encodeCommand(&packet, command);
        const rc = std.os.linux.write(self.fd, bytes.ptr, bytes.len);
        if (std.posix.errno(rc) != .SUCCESS or rc != bytes.len) return error.SendFailed;
    }
    pub fn receive(self: Client, buffer: []u8) !Event {
        const rc = std.os.linux.read(self.fd, buffer.ptr, buffer.len);
        if (std.posix.errno(rc) != .SUCCESS) return error.ReceiveFailed;
        if (rc == 0 or rc == buffer.len) return error.Closed;
        return parseEvent(buffer[0..rc]);
    }
};
test "secret is encoded and scrubbed" {
    var command = bluetooth.Command{ .generation = 2, .request_id = 3, .kind = .submit_passkey, .secret_len = 6 };
    @memcpy(command.secret[0..6], "123456");
    var packet: [512]u8 = undefined;
    const encoded = try encodeCommand(&packet, &command);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "secret=123456") != null);
    try std.testing.expectEqual(@as(u8, 0), command.secret_len);
}
