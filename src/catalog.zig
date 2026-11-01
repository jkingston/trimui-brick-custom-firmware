// SPDX-License-Identifier: GPL-2.0-only

pub const Cover = enum { library, falling, minekart };

pub const Game = struct {
    title: []const u8,
    system: []const u8,
    summary: []const u8,
    core_path: []const u8,
    rom_path: []const u8,
    cover: Cover,
};

pub const games = [_]Game{
    .{
        .title = "FALLING",
        .system = "NINTENDO NES",
        .summary = "ARCADE PLATFORMER",
        .core_path = "/usr/lib/libretro/fceumm_libretro.so",
        .rom_path = "/data/roms/nes/falling.nes",
        .cover = .falling,
    },
    .{
        .title = "MINEKART MADNESS",
        .system = "NINTENDO NES",
        .summary = "HIGH SPEED RAILS",
        .core_path = "/usr/lib/libretro/fceumm_libretro.so",
        .rom_path = "/data/roms/nes/minekart-madness.nes",
        .cover = .minekart,
    },
};
