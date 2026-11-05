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
    .background = rgb(0xf5f4f0),
    .surface = rgb(0xe7e7e1),
    .text = rgb(0x202122),
    .muted = rgb(0x646660),
    .accent = rgb(0x202122),
    .selection = rgb(0x202122),
    .selection_text = rgb(0xf5f4f0),
    .border = rgb(0xb9bcb4),
    .shadow = rgb(0xa0a1a8),
    .danger = rgb(0xa72d32),
    .scrim = rgb(0x202122),
    .on_scrim = rgb(0xf5f4f0),
};
pub const dark = Theme{
    .background = rgb(0x171819),
    .surface = rgb(0x30322e),
    .text = rgb(0xf5f4f0),
    .muted = rgb(0xabb0a6),
    .accent = rgb(0xeeefec),
    .selection = rgb(0xeeefec),
    .selection_text = rgb(0x171819),
    .border = rgb(0x575b53),
    .shadow = rgb(0x08080a),
    .danger = rgb(0xff9a91),
    .scrim = rgb(0x08080a),
    .on_scrim = rgb(0xf5f4f0),
};
