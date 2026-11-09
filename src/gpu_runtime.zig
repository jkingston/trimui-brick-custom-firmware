// SPDX-License-Identifier: GPL-2.0-only
// The vendor EGL library dlopens unversioned GLES names. The loader's private
// search path applies to this process, unlike LD_LIBRARY_PATH it is not inherited
// by games/browser helpers. No system EGL library is overwritten.
const std = @import("std");
extern "c" fn readlink([*:0]const u8, [*]u8, usize) isize;
extern "c" fn execv([*:0]const u8, [*:null]const ?[*:0]const u8) c_int;

pub fn enter(arguments: std.process.Args) !void {
    var path: [4096]u8 = @splat(0);
    const length = readlink("/proc/self/exe", &path, path.len - 1);
    if (length <= 0 or length >= path.len - 1) return error.ExecutablePath;
    const loader = "/lib/ld-linux-aarch64.so.1";
    var argv: [40:null]?[*:0]const u8 = @splat(null);
    argv[0] = loader;
    argv[1] = "--library-path";
    argv[2] = "/usr/lib/brick-gpu";
    argv[3] = @ptrCast(&path);
    argv[4] = "--gpu-runtime";
    var iterator = std.process.Args.Iterator.init(arguments);
    _ = iterator.next();
    var count: usize = 5;
    while (iterator.next()) |argument| {
        if (count == argv.len) return error.TooManyArguments;
        argv[count] = argument.ptr;
        count += 1;
    }
    _ = execv(loader, &argv);
    return error.GpuLoaderExec;
}
