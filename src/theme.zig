// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
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
    .background = rgb(0xf1f0ea),
    .surface = rgb(0xe3e2dc),
    .text = rgb(0x0d1111),
    .muted = rgb(0x626a69),
    .accent = rgb(0x00757c),
    .selection = rgb(0x0d1111),
    .selection_text = rgb(0xf7f7f2),
    .border = rgb(0xc4c8c5),
    .shadow = rgb(0x999e9b),
    .focus_shadow = rgb(0xd3d5d1),
    .danger = rgb(0xb43a42),
    .scrim = rgb(0x090c0c),
    .on_scrim = rgb(0xf2f2ec),
};
pub const dark = Theme{
    .background = rgb(0x090c0c),
    .surface = rgb(0x171c1c),
    .text = rgb(0xf2f2ec),
    .muted = rgb(0x929b99),
    .accent = rgb(0x59d4cf),
    .selection = rgb(0xf2f2ec),
    .selection_text = rgb(0x090c0c),
    .border = rgb(0x343c3b),
    .shadow = rgb(0x020303),
    .focus_shadow = rgb(0x030505),
    .danger = rgb(0xff777f),
    .scrim = rgb(0x050707),
    .on_scrim = rgb(0xf2f2ec),
};

fn linearChannel(value: u8) f64 {
    const channel: f64 = @as(f64, @floatFromInt(value)) / 255.0;
    return if (channel <= 0.04045) channel / 12.92 else std.math.pow(f64, (channel + 0.055) / 1.055, 2.4);
}

fn luminance(color: Color) f64 {
    return 0.2126 * linearChannel(color.r) + 0.7152 * linearChannel(color.g) + 0.0722 * linearChannel(color.b);
}

fn contrast(first: Color, second: Color) f64 {
    const a = luminance(first);
    const b = luminance(second);
    return (@max(a, b) + 0.05) / (@min(a, b) + 0.05);
}

test "semantic text colours remain legible in both appearances" {
    for ([_]Theme{ light, dark }) |theme| {
        try std.testing.expect(contrast(theme.text, theme.background) >= 7.0);
        try std.testing.expect(contrast(theme.muted, theme.background) >= 4.5);
        try std.testing.expect(contrast(theme.accent, theme.background) >= 4.5);
        try std.testing.expect(contrast(theme.danger, theme.background) >= 4.5);
        try std.testing.expect(contrast(theme.selection_text, theme.selection) >= 7.0);
    }
}
