// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const assets = @import("asset_manifest.zig");
const design = @import("design.zig");
const interaction = @import("interaction.zig");
const font = design.typeface;

pub const Color = @import("color.zig").Color;
pub const Theme = @import("theme.zig").Theme;

pub const Rect = struct { x: u16, y: u16, width: u16, height: u16 };
pub const Text = struct { bounds: Rect, value: []const u8, color: Color, font: design.Font = font.body, language: []const u8 = "", lines: u8 = 1 };
pub const TextBlock = struct {
    bounds: Rect,
    title: []const u8,
    detail: []const u8,
    color: Color,
    detail_color: Color,
    title_font: design.Font = font.body,
    detail_font: design.Font = font.caption,
    lines: u8 = 2,
    detail_lines: u8 = 1,
    gap: u16 = 16,
    centered: bool = false,
    detail_above: bool = false,
};
pub const Bar = struct { bounds: Rect, color: Color, radius: u16 = 0 };
pub const Scrim = struct { bounds: Rect, color: Color, alpha: u8 };
pub const RowStyle = struct {
    background: Color,
    text: Color,
    detail: Color,
    border: Color,
    accent: Color,
};
pub const ArtworkStyle = struct { shadow: Color, edge: Color, surface: Color, text: Color };
pub const MenuRow = struct {
    id: interaction.Id = .none,
    state: interaction.State = .idle,
    label_font: design.Font = font.body,
    lines: u8 = 1,
    style: RowStyle = std.mem.zeroes(RowStyle),
    bounds: Rect,
    label: []const u8,
    detail: []const u8 = "",
    // Compatibility input for existing views. Tree.add resolves it into state;
    // new components should set state explicitly.
    selected: bool = false,
    disclosure: bool = true,
};
pub const Battery = struct { bounds: Rect, percent: u8, outline: Color = std.mem.zeroes(Color), charge: Color = std.mem.zeroes(Color) };
pub const QrCode = struct { bounds: Rect, cells: []const u8, width: u16, foreground: Color, background: Color };
pub const Keyboard = struct { bounds: Rect, selected: u8, uppercase: bool = false, symbols: bool = false };
pub const KeyboardKey = struct { keyboard: Keyboard, index: u8, bounds: Rect };
pub const CoverKind = @import("cover_kind.zig").Kind;
pub const Cover = struct { bounds: Rect, kind: CoverKind };
pub const Cartridge = struct {
    style: ArtworkStyle = std.mem.zeroes(ArtworkStyle),
    bounds: Rect,
    platform: []const u8,
    texture: ?assets.Texture,
    sprite: ?assets.Texture,
    selected: bool = false,
    dim: u8 = 0,
    tilt: i16 = 0,
    clip_left: u16 = 0,
    plain_fallback: bool = false,
};
pub const OverlayRow = struct {
    id: interaction.Id = .none,
    state: interaction.State = .idle,
    style: RowStyle = std.mem.zeroes(RowStyle),
    bounds: Rect,
    label: []const u8,
    detail: []const u8,
    value: []const u8 = "",
    selected: bool = false,
    disclosure: bool = true,
};
pub const Element = union(enum) {
    bar: Bar,
    scrim: Scrim,
    text: Text,
    text_block: TextBlock,
    menu_row: MenuRow,
    battery: Battery,
    qr_code: QrCode,
    keyboard: Keyboard,
    keyboard_key: KeyboardKey,
    cover: Cover,
    cartridge: Cartridge,
    overlay_row: OverlayRow,
};

pub const maximum_elements = 48;

pub const Tree = struct {
    theme: Theme = @import("theme.zig").light,
    background: Color,
    preserve_background: bool = false,
    // SAFETY: Only the initialized prefix exposed by slice() is read.
    elements: [maximum_elements]Element = undefined,
    len: usize = 0,

    pub fn add(self: *Tree, element: Element) void {
        if (self.len == self.elements.len) @panic("UI scene capacity exceeded");
        var resolved = element;
        switch (resolved) {
            .menu_row => |*row| {
                if (row.id == .none) row.id = interaction.Id.scoped(.implicit_menu, self.len);
                if (row.selected and row.state == .idle) row.state = .focused;
                row.selected = row.state.hasFocus();
                row.style = self.rowStyle(row.state);
            },
            .overlay_row => |*row| {
                if (row.id == .none) row.id = interaction.Id.scoped(.implicit_overlay, self.len);
                if (row.selected and row.state == .idle) row.state = .focused;
                row.selected = row.state.hasFocus();
                row.style = self.rowStyle(row.state);
            },
            .cartridge => |*item| item.style = .{ .shadow = self.theme.shadow, .edge = if (item.selected) self.theme.accent else self.theme.border, .surface = self.theme.surface, .text = self.theme.muted },
            .battery => |*item| {
                item.outline = self.theme.text;
                item.charge = self.theme.accent;
            },
            else => {},
        }
        self.elements[self.len] = resolved;
        self.len += 1;
    }

    fn rowStyle(self: *const Tree, state: interaction.State) RowStyle {
        const selected = state.hasFocus();
        const pressed = state == .pressed;
        const disabled = state == .disabled;
        return .{
            .background = if (pressed) self.theme.background else if (selected) self.theme.selection else self.theme.background,
            .text = if (disabled) self.theme.muted else if (pressed) self.theme.text else if (selected) self.theme.selection_text else self.theme.text,
            .detail = if (disabled) self.theme.muted else if (pressed) self.theme.muted else if (selected) self.theme.selection_text else self.theme.muted,
            .border = if (pressed) self.theme.selection else self.theme.border,
            .accent = self.theme.accent,
        };
    }

    pub fn focusedId(self: *const Tree) ?interaction.Id {
        for (self.slice()) |element| switch (element) {
            .menu_row => |row| if (row.state.hasFocus()) return row.id,
            .overlay_row => |row| if (row.state.hasFocus()) return row.id,
            else => {},
        };
        return null;
    }

    /// Apply transient interaction state after a view has declared its content.
    /// This keeps press/busy styling out of individual screen builders.
    pub fn setInteraction(self: *Tree, id: interaction.Id, state: interaction.State) bool {
        for (self.elements[0..self.len]) |*element| switch (element.*) {
            .menu_row => |*row| if (row.id == id) {
                row.state = state;
                row.selected = state.hasFocus();
                row.style = self.rowStyle(state);
                return true;
            },
            .overlay_row => |*row| if (row.id == id) {
                row.state = state;
                row.selected = state.hasFocus();
                row.style = self.rowStyle(state);
                return true;
            },
            else => {},
        };
        return false;
    }

    pub fn slice(self: *const Tree) []const Element {
        return self.elements[0..self.len];
    }

    pub fn validate(self: *const Tree) !void {
        for (self.slice()) |element| {
            const bounds = switch (element) {
                inline else => |value| value.bounds,
            };
            const intentionally_clipped = element == .cartridge;
            if (!intentionally_clipped and (@as(u32, bounds.x) + bounds.width > design.geometry.width or
                @as(u32, bounds.y) + bounds.height > design.geometry.height))
                return error.ElementOutsideScreen;
            switch (element) {
                .overlay_row => |row| if (row.detail.len != 0 and row.bounds.height < design.typeface.body.line_height + 6 + design.typeface.caption.line_height)
                    return error.SupportingRowTooShort,
                .menu_row => |row| if (row.detail.len != 0 and row.bounds.height < design.typeface.body.line_height + 6 + design.typeface.caption.line_height)
                    return error.SupportingRowTooShort,
                else => {},
            }
        }
    }
};

test "scene capacity fails at the construction boundary" {
    var tree = Tree{ .background = .{ .r = 0, .g = 0, .b = 0 } };
    for (0..maximum_elements) |_| tree.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 0, .width = 1, .height = 1 }, .color = tree.background } });
    try std.testing.expectEqual(maximum_elements, tree.slice().len);
}

test "scene validation rejects overflowing and undersized supporting rows" {
    var tree = Tree{ .background = .{ .r = 0, .g = 0, .b = 0 } };
    tree.add(.{ .bar = .{ .bounds = .{ .x = 1000, .y = 0, .width = 40, .height = 10 }, .color = tree.background } });
    try std.testing.expectError(error.ElementOutsideScreen, tree.validate());
    tree.len = 0;
    tree.add(.{ .overlay_row = .{ .bounds = .{ .x = 0, .y = 0, .width = 100, .height = 88 }, .label = "Network", .detail = "Connected", .selected = false } });
    try std.testing.expectError(error.SupportingRowTooShort, tree.validate());
}

test "tree resolves selection into durable interaction state" {
    var tree = Tree{ .background = .{ .r = 0, .g = 0, .b = 0 } };
    tree.add(.{ .menu_row = .{ .bounds = .{ .x = 0, .y = 0, .width = 100, .height = 88 }, .label = "Play", .selected = true } });
    const id = tree.focusedId().?;
    try std.testing.expectEqual(interaction.State.focused, tree.elements[0].menu_row.state);
    try std.testing.expect(tree.setInteraction(id, .pressed));
    try std.testing.expectEqual(interaction.State.pressed, tree.elements[0].menu_row.state);
    try std.testing.expect(tree.elements[0].menu_row.selected);
}
