// SPDX-License-Identifier: GPL-2.0-only
pub const Color = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    a: u8 = 0xff,
};
