// SPDX-License-Identifier: GPL-2.0-only
const ui = @import("ui_scene.zig");
const assets = @import("artwork_store.zig");
// Immediate consumption: borrowed text/artwork data must not outlive the call.
pub const Sink = struct {
    context: *anyopaque,
    clip: *const fn (*anyopaque, []const ui.Rect) void,
    fill: *const fn (*anyopaque, ui.Rect, ui.Color, u8) void,
    mask: *const fn (*anyopaque, u64, u16, u16, []const u8, u16, u16, u32) void,
    texture: *const fn (*anyopaque, assets.Texture, ui.Rect, u8, i16, u16) void,
};
