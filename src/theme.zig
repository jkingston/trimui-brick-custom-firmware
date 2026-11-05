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
    .background = rgb(0xf3f1e9),
    .surface = rgb(0xe7e9df),
    .text = rgb(0x14211b),
    .muted = rgb(0x58675e),
    .accent = rgb(0x236a53),
    .selection = rgb(0xd8e5dc),
    .selection_text = rgb(0x236a53),
    .border = rgb(0xcbd0c8),
    .shadow = rgb(0x9da8a0),
    .danger = rgb(0xa72d32),
    .scrim = rgb(0x102820),
    .on_scrim = rgb(0xfffef9),
};
pub const dark = Theme{
    .background = rgb(0x141c19),
    .surface = rgb(0x202d26),
    .text = rgb(0xf0f1e8),
    .muted = rgb(0xaab8af),
    .accent = rgb(0x9cd3b4),
    .selection = rgb(0x2b4738),
    .selection_text = rgb(0x9cd3b4),
    .border = rgb(0x3c4d43),
    .shadow = rgb(0x080e0a),
    .danger = rgb(0xff9a91),
    .scrim = rgb(0x08110d),
    .on_scrim = rgb(0xfffef9),
};
