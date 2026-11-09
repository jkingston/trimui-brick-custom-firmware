// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
extern "c" fn open([*:0]const u8, c_int, ...) c_int;
extern "c" fn close(c_int) c_int;
extern "c" fn write(c_int, [*]const u8, usize) isize;
extern "c" fn usleep(c_uint) c_int;

const Event = extern struct {
    seconds: i64 = 0,
    microseconds: i64 = 0,
    kind: u16 = 0,
    code: u16 = 0,
    value: i32 = 0,
};

fn send(fd: c_int, code: u16, value: i32) !void {
    const events = [_]Event{ .{ .kind = 1, .code = code, .value = value }, .{} };
    const bytes = std.mem.asBytes(&events);
    if (write(fd, bytes, bytes.len) != bytes.len) return error.InputWrite;
}

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const path = args.next() orelse return error.MissingEventDevice;
    const fd = open(path.ptr, 0x80001);
    if (fd < 0) return error.InputOpen;
    defer _ = close(fd);
    while (args.next()) |key| {
        if (std.mem.eql(u8, key, "--sweep") or std.mem.eql(u8, key, "--sweep-horizontal")) {
            const horizontal = std.mem.eql(u8, key, "--sweep-horizontal");
            const period_us = try std.fmt.parseInt(u32, args.next() orelse return error.MissingPeriod, 10);
            const count = try std.fmt.parseInt(u32, args.next() orelse return error.MissingCount, 10);
            if (period_us < 2000 or period_us > 1_000_000 or count == 0 or count > 10000) return error.InvalidSweep;
            for (0..count) |index| {
                const code: u16 = if (horizontal) (if (index % 12 < 6) 0x223 else 0x222) else if (index % 12 < 6) 0x221 else 0x220;
                try send(fd, code, 1);
                _ = usleep(1000);
                try send(fd, code, 0);
                _ = usleep(period_us - 1000);
            }
            return;
        }
        const code: u16 = if (std.mem.eql(u8, key, "up")) 0x220 else if (std.mem.eql(u8, key, "down")) 0x221 else if (std.mem.eql(u8, key, "a")) 0x131 else if (std.mem.eql(u8, key, "b")) 0x130 else return error.UnsupportedKey;
        try send(fd, code, 1);
        _ = usleep(40000);
        try send(fd, code, 0);
        _ = usleep(160000);
    }
}
