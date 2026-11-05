// SPDX-License-Identifier: GPL-2.0-only
const Color = @import("color.zig").Color;

pub const Mode = enum {
    light,
    dark,

    pub fn colors(self: Mode) Theme {
        return switch (self) {
            .light => light,
            .dark => dark,
        };
    }
};

// Plain values, resolved when constructing a frame; no style engine or allocations.
pub const Theme = struct {
    background: Color,
    surface: Color,
    text: Color,
    muted: Color,
    accent: Color,
    selection: Color,
    selection_text: Color,
    border: Color,
    shadow: Color,
    danger: Color,
    scrim: Color,
    on_scrim: Color,
};

fn rgb(comptime hex: u24) Color {
    return .{ .r = @truncate(hex >> 16), .g = @truncate(hex >> 8), .b = @truncate(hex) };
}

pub const light = Theme{
    .background = rgb(0xf5f5f7),
    .surface = rgb(0xe9e9ed),
    .text = rgb(0x202124),
    .muted = rgb(0x686a70),
    .accent = rgb(0x2463cc),
    .selection = rgb(0x2463cc),
    .selection_text = rgb(0xffffff),
    .border = rgb(0xc7c8ce),
    .shadow = rgb(0xa0a1a8),
    .danger = rgb(0xa72d32),
    .scrim = rgb(0x202124),
    .on_scrim = rgb(0xffffff),
};
pub const dark = Theme{
    .background = rgb(0x151518),
    .surface = rgb(0x252529),
    .text = rgb(0xf5f5f7),
    .muted = rgb(0xaaaab2),
    .accent = rgb(0x80b1ff),
    .selection = rgb(0x376fce),
    .selection_text = rgb(0xffffff),
    .border = rgb(0x484850),
    .shadow = rgb(0x08080a),
    .danger = rgb(0xff9a91),
    .scrim = rgb(0x08080a),
    .on_scrim = rgb(0xffffff),
};
