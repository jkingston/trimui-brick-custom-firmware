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
    .background = rgb(0xf3efe8),
    .surface = rgb(0xe4dfd6),
    .text = rgb(0x191a1d),
    .muted = rgb(0x68666a),
    .accent = rgb(0x176c92),
    .selection = rgb(0x191a1d),
    .selection_text = rgb(0xf7f3ec),
    .border = rgb(0xc9c3ba),
    .shadow = rgb(0xa9a39a),
    .focus_shadow = rgb(0xd2ccc4),
    .danger = rgb(0xa93442),
    .scrim = rgb(0x090b0e),
    .on_scrim = rgb(0xf5f2ed),
};
pub const dark = Theme{
    .background = rgb(0x0b0d10),
    .surface = rgb(0x1a1d22),
    .text = rgb(0xf5f2ed),
    .muted = rgb(0x9998a0),
    .accent = rgb(0xa5d9ff),
    .selection = rgb(0xf5f2ed),
    .selection_text = rgb(0x0b0d10),
    .border = rgb(0x343840),
    .shadow = rgb(0x030406),
    .focus_shadow = rgb(0x050609),
    .danger = rgb(0xff7a86),
    .scrim = rgb(0x07090c),
    .on_scrim = rgb(0xf5f2ed),
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
