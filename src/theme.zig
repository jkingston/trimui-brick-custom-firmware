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
    focus_shadow: Color,
    danger: Color,
    scrim: Color,
    on_scrim: Color,
};

fn rgb(comptime hex: u24) Color {
    return .{ .r = @truncate(hex >> 16), .g = @truncate(hex >> 8), .b = @truncate(hex) };
}

pub const light = Theme{
    .background = rgb(0xf3f1e9),
    .surface = rgb(0xe8e7df),
    .text = rgb(0x14211b),
    .muted = rgb(0x626861),
    .accent = rgb(0x14211b),
    .selection = rgb(0x14211b),
    .selection_text = rgb(0xfffef9),
    .border = rgb(0xc2c5bd),
    .shadow = rgb(0xa0a1a8),
    .focus_shadow = rgb(0xd2d2ca),
    .danger = rgb(0xa72d32),
    .scrim = rgb(0x202122),
    .on_scrim = rgb(0xf5f4f0),
};
pub const dark = Theme{
    .background = rgb(0x111512),
    .surface = rgb(0x292e2a),
    .text = rgb(0xf3f1e9),
    .muted = rgb(0xaab0a8),
    .accent = rgb(0xf3f1e9),
    .selection = rgb(0xf3f1e9),
    .selection_text = rgb(0x14211b),
    .border = rgb(0x505750),
    .shadow = rgb(0x08080a),
    .focus_shadow = rgb(0x070907),
    .danger = rgb(0xff9a91),
    .scrim = rgb(0x08080a),
    .on_scrim = rgb(0xf5f4f0),
};
