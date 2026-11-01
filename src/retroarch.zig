// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const catalog = @import("catalog.zig");

pub const executable = "/usr/bin/retroarch";
pub const config_path = "/etc/retroarch/retroarch.cfg";

pub fn arguments(game: *const catalog.Game) [6][]const u8 {
    return .{ executable, "--config", config_path, "-L", game.core_path, game.rom_path };
}

pub fn launch(io: std.Io, game: *const catalog.Game) !std.process.Child.Term {
    const argv = arguments(game);
    var child = try std.process.spawn(io, .{ .argv = &argv });
    return child.wait(io);
}

test "launch contract uses an explicit core, config and content path" {
    const argv = arguments(&catalog.games[0]);
    try std.testing.expectEqualStrings(executable, argv[0]);
    try std.testing.expectEqualStrings("--config", argv[1]);
    try std.testing.expectEqualStrings(config_path, argv[2]);
    try std.testing.expectEqualStrings("-L", argv[3]);
    try std.testing.expectEqualStrings("/usr/lib/libretro/fceumm_libretro.so", argv[4]);
    try std.testing.expectEqualStrings("/data/roms/nes/falling.nes", argv[5]);
}
