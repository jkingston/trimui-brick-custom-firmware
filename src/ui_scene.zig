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
    base: Color,
    background: Color,
    text: Color,
    detail: Color,
    border: Color,
    accent: Color,
    shadow: Color,
};
pub const FrameStyle = struct { base: Color, background: Color, border: Color, shadow: Color };
pub const ArtworkStyle = struct { shadow: Color, edge: Color, surface: Color, text: Color };
pub const CardEmphasis = enum { primary, secondary };
/// Focus is not synonymous with a filled card. Editorial surfaces use content
/// hierarchy plus an interaction anchor; dense utility views may use a plate.
pub const FocusPresentation = enum { plate, quiet };
pub const FocusFrame = struct {
    id: interaction.Id = .none,
    state: interaction.State = .idle,
    style: FrameStyle = std.mem.zeroes(FrameStyle),
    bounds: Rect,
    presentation: FocusPresentation = .plate,
    focus_offset_x: i16 = 0,
    focus_offset_y: i16 = 0,
    activity_phase: u16 = 0,
    activity_animated: bool = true,

    pub fn displayedBounds(self: FocusFrame) Rect {
        return offsetBounds(self.bounds, self.focus_offset_x, self.focus_offset_y);
    }
};
pub const MenuRow = struct {
    id: interaction.Id = .none,
    state: interaction.State = .idle,
    label_font: design.Font = font.body,
    lines: u8 = 1,
    style: RowStyle = std.mem.zeroes(RowStyle),
    bounds: Rect,
    label: []const u8,
    detail: []const u8 = "",
    focus_offset_x: i16 = 0,
    focus_offset_y: i16 = 0,
    // Compatibility input for existing views. Tree.add resolves it into state;
    // new components should set state explicitly.
    selected: bool = false,
    disclosure: bool = true,
    activity_phase: u16 = 0,
    activity_animated: bool = true,

    pub fn displayedBounds(self: MenuRow) Rect {
        return offsetBounds(self.bounds, self.focus_offset_x, self.focus_offset_y);
    }
};
/// A spatial navigation target for landing and overview surfaces. It shares the
/// same interaction contract as rows; only its content hierarchy is different.
pub const ActionCard = struct {
    id: interaction.Id = .none,
    state: interaction.State = .idle,
    style: RowStyle = std.mem.zeroes(RowStyle),
    bounds: Rect,
    eyebrow: []const u8,
    label: []const u8,
    detail: []const u8 = "",
    emphasis: CardEmphasis = .secondary,
    label_lines: u8 = 1,
    detail_lines: u8 = 1,
    focus_offset_x: i16 = 0,
    focus_offset_y: i16 = 0,
    focus_width_delta: i16 = 0,
    focus_height_delta: i16 = 0,
    activity_phase: u16 = 0,
    activity_animated: bool = true,

    pub fn displayedBounds(self: ActionCard) Rect {
        const width: u16 = @intCast(std.math.clamp(@as(i32, self.bounds.width) + self.focus_width_delta, 1, @as(i32, design.geometry.width)));
        const height: u16 = @intCast(std.math.clamp(@as(i32, self.bounds.height) + self.focus_height_delta, 1, @as(i32, design.geometry.height)));
        return .{
            .x = @intCast(std.math.clamp(@as(i32, self.bounds.x) + self.focus_offset_x, 0, @as(i32, design.geometry.width -| width))),
            .y = @intCast(std.math.clamp(@as(i32, self.bounds.y) + self.focus_offset_y, 0, @as(i32, design.geometry.height -| height))),
            .width = width,
            .height = height,
        };
    }
};
pub const Battery = struct { bounds: Rect, percent: u8, outline: Color = std.mem.zeroes(Color), charge: Color = std.mem.zeroes(Color) };
pub const Wifi = struct { bounds: Rect, arcs: Color, dot: Color };
pub const Headphones = struct { bounds: Rect, color: Color };
pub const MeterPresentation = enum { continuous, stepped };
pub const Meter = struct {
    id: interaction.Id,
    bounds: Rect,
    value: u16,
    visible: bool = true,
    track: Color,
    fill: Color,
    thumb: Color,
    presentation: MeterPresentation = .continuous,
    steps: u8 = 0,
};
pub const Activity = struct { bounds: Rect, color: Color, phase: u16 = 0, animated: bool = true };
pub const QrCode = struct { bounds: Rect, cells: []const u8, width: u16, foreground: Color, background: Color };
pub const Keyboard = struct {
    id: interaction.Id = .none,
    state: interaction.State = .focused,
    bounds: Rect,
    selected: u8,
    uppercase: bool = false,
    symbols: bool = false,
    focus_offset_x: i16 = 0,
    focus_offset_y: i16 = 0,

    pub fn keyBounds(self: Keyboard, index: usize) Rect {
        const columns = 10;
        const rows = 4;
        const gap = 8;
        const item = @min(index, columns * rows - 1);
        const width = (self.bounds.width - gap * (columns - 1)) / columns;
        const height = (self.bounds.height - gap * (rows - 1)) / rows;
        return .{
            .x = self.bounds.x + @as(u16, @intCast(item % columns)) * (width + gap),
            .y = self.bounds.y + @as(u16, @intCast(item / columns)) * (height + gap),
            .width = width,
            .height = height,
        };
    }

    pub fn selectedBounds(self: Keyboard) Rect {
        return self.keyBounds(@min(self.selected, 39));
    }

    pub fn displayedBounds(self: Keyboard) Rect {
        const bounds = self.selectedBounds();
        return .{
            .x = @intCast(std.math.clamp(@as(i32, bounds.x) + self.focus_offset_x, 0, std.math.maxInt(u16))),
            .y = @intCast(std.math.clamp(@as(i32, bounds.y) + self.focus_offset_y, 0, std.math.maxInt(u16))),
            .width = bounds.width,
            .height = bounds.height,
        };
    }
};
pub const KeyboardKey = struct { keyboard: Keyboard, index: u8, bounds: Rect };
pub const CoverKind = @import("cover_kind.zig").Kind;
pub const Cover = struct { bounds: Rect, kind: CoverKind };
pub const Cartridge = struct {
    id: interaction.Id = .none,
    state: interaction.State = .idle,
    style: ArtworkStyle = std.mem.zeroes(ArtworkStyle),
    bounds: Rect,
    platform: []const u8,
    texture: ?assets.Texture,
    sprite: ?assets.Texture,
    selected: bool = false,
    focus_offset_x: i16 = 0,
    focus_offset_y: i16 = 0,
    dim: u8 = 0,
    tilt: i16 = 0,
    clip_left: u16 = 0,
    pub fn displayBounds(self: Cartridge) Rect {
        return .{
            .x = @intCast(std.math.clamp(@as(i32, self.bounds.x) + self.focus_offset_x, 0, std.math.maxInt(u16))),
            .y = @intCast(std.math.clamp(@as(i32, self.bounds.y) + self.focus_offset_y, 0, std.math.maxInt(u16))),
            .width = self.bounds.width,
            .height = self.bounds.height,
        };
    }
};
pub const OverlayRow = struct {
    id: interaction.Id = .none,
    state: interaction.State = .idle,
    style: RowStyle = std.mem.zeroes(RowStyle),
    bounds: Rect,
    label: []const u8,
    detail: []const u8,
    value: []const u8 = "",
    focus_offset_x: i16 = 0,
    focus_offset_y: i16 = 0,
    selected: bool = false,
    disclosure: bool = true,
    activity_phase: u16 = 0,
    activity_animated: bool = true,

    pub fn displayedBounds(self: OverlayRow) Rect {
        return offsetBounds(self.bounds, self.focus_offset_x, self.focus_offset_y);
    }
};

fn offsetBounds(bounds: Rect, offset_x: i16, offset_y: i16) Rect {
    return .{
        .x = @intCast(std.math.clamp(@as(i32, bounds.x) + offset_x, 0, @as(i32, design.geometry.width -| bounds.width))),
        .y = @intCast(std.math.clamp(@as(i32, bounds.y) + offset_y, 0, @as(i32, design.geometry.height -| bounds.height))),
        .width = bounds.width,
        .height = bounds.height,
    };
}

pub fn stateAffordanceWidth(state: interaction.State) u16 {
    return switch (state) {
        .busy, .succeeded, .failed => 54,
        else => 0,
    };
}
pub const Element = union(enum) {
    bar: Bar,
    scrim: Scrim,
    text: Text,
    text_block: TextBlock,
    focus_frame: FocusFrame,
    menu_row: MenuRow,
    action_card: ActionCard,
    battery: Battery,
    wifi: Wifi,
    headphones: Headphones,
    meter: Meter,
    activity: Activity,
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
            .focus_frame => |*frame| {
                if (frame.id == .none) frame.id = interaction.Id.scoped(.implicit_frame, self.len);
                frame.style = self.frameStyle(frame.state);
            },
            .menu_row => |*row| {
                if (row.id == .none) row.id = interaction.Id.scoped(.implicit_menu, self.len);
                if (row.selected and row.state == .idle) row.state = .focused;
                row.selected = row.state.hasFocus();
                row.style = self.rowStyle(row.state);
            },
            .action_card => |*card| {
                if (card.id == .none) card.id = interaction.Id.scoped(.implicit_frame, self.len);
                card.style = self.rowStyle(card.state);
            },
            .overlay_row => |*row| {
                if (row.id == .none) row.id = interaction.Id.scoped(.implicit_overlay, self.len);
                if (row.selected and row.state == .idle) row.state = .focused;
                row.selected = row.state.hasFocus();
                row.style = self.rowStyle(row.state);
            },
            .cartridge => |*item| {
                item.selected = item.selected or item.state.hasFocus();
                item.style = .{ .shadow = self.theme.shadow, .edge = self.theme.border, .surface = self.theme.surface, .text = self.theme.muted };
            },
            .battery => |*item| {
                item.outline = self.theme.text;
                item.charge = self.theme.accent;
            },
            .keyboard => |*item| {
                item.selected = @min(item.selected, 39);
                if (item.id == .none) item.id = interaction.Id.scoped(.keyboard_key, item.selected);
            },
            else => {},
        }
        self.elements[self.len] = resolved;
        self.len += 1;
    }

    fn rowStyle(self: *const Tree, state: interaction.State) RowStyle {
        const pressed = state == .pressed or state == .activating;
        const disabled = state == .disabled;
        const failed = state == .failed;
        return .{
            .base = self.theme.background,
            // Focus changes hierarchy; it does not turn every control into a
            // card. The renderer adds one shared baseline. Press is the only
            // momentary filled state.
            .background = if (pressed) self.theme.selection else self.theme.background,
            .text = if (disabled) self.theme.muted else if (pressed) self.theme.selection_text else self.theme.text,
            .detail = if (disabled) self.theme.muted else if (pressed) self.theme.selection_text else self.theme.muted,
            .border = if (failed) self.theme.danger else if (state == .boundary) self.theme.accent else if (pressed) self.theme.selection else self.theme.background,
            .accent = if (failed) self.theme.danger else if (disabled) self.theme.muted else self.theme.accent,
            .shadow = self.theme.background,
        };
    }

    fn frameStyle(self: *const Tree, state: interaction.State) FrameStyle {
        const selected = state.hasFocus();
        const pressed = state == .pressed or state == .activating;
        const failed = state == .failed;
        return .{
            .base = self.theme.background,
            .background = if (pressed) self.theme.selection else if (selected) self.theme.surface else self.theme.background,
            .border = if (failed) self.theme.danger else if (pressed) self.theme.selection_text else if (selected) self.theme.accent else self.theme.background,
            .shadow = self.theme.focus_shadow,
        };
    }

    pub fn focusedId(self: *const Tree) ?interaction.Id {
        for (self.slice()) |element| switch (element) {
            .focus_frame => |frame| if (frame.state.hasFocus()) return frame.id,
            .menu_row => |row| if (row.state.hasFocus()) return row.id,
            .action_card => |card| if (card.state.hasFocus()) return card.id,
            .cartridge => |item| if (item.state.hasFocus()) return item.id,
            .overlay_row => |row| if (row.state.hasFocus()) return row.id,
            .keyboard => |item| if (item.state.hasFocus()) return item.id,
            else => {},
        };
        return null;
    }

    pub const Focus = struct { id: interaction.Id, bounds: Rect };

    pub fn focus(self: *const Tree) ?Focus {
        for (self.slice()) |element| switch (element) {
            .focus_frame => |frame| if (frame.state.hasFocus()) return .{ .id = frame.id, .bounds = frame.bounds },
            .menu_row => |row| if (row.state.hasFocus()) return .{ .id = row.id, .bounds = row.bounds },
            .action_card => |card| if (card.state.hasFocus()) return .{ .id = card.id, .bounds = card.bounds },
            .cartridge => |item| if (item.state.hasFocus()) return .{ .id = item.id, .bounds = item.bounds },
            .overlay_row => |row| if (row.state.hasFocus()) return .{ .id = row.id, .bounds = row.bounds },
            .keyboard => |item| if (item.state.hasFocus()) return .{ .id = item.id, .bounds = item.selectedBounds() },
            else => {},
        };
        return null;
    }

    /// Apply transient interaction state after a view has declared its content.
    /// This keeps press/busy styling out of individual screen builders.
    pub fn setInteraction(self: *Tree, id: interaction.Id, state: interaction.State) bool {
        for (self.elements[0..self.len]) |*element| switch (element.*) {
            .focus_frame => |*frame| if (frame.id == id) {
                frame.state = state;
                frame.style = self.frameStyle(state);
                return true;
            },
            .menu_row => |*row| if (row.id == id) {
                row.state = state;
                row.selected = state.hasFocus();
                row.style = self.rowStyle(state);
                return true;
            },
            .action_card => |*card| if (card.id == id) {
                card.state = state;
                card.style = self.rowStyle(state);
                return true;
            },
            .overlay_row => |*row| if (row.id == id) {
                row.state = state;
                row.selected = state.hasFocus();
                row.style = self.rowStyle(state);
                return true;
            },
            .cartridge => |*item| if (item.id == id) {
                item.state = state;
                item.selected = state.hasFocus();
                item.style.edge = if (state == .failed) self.theme.danger else self.theme.border;
                return true;
            },
            .keyboard => |*item| if (item.id == id) {
                item.state = state;
                return true;
            },
            else => {},
        };
        return false;
    }

    pub fn setFocusOffset(self: *Tree, id: interaction.Id, offset_x: i16, offset_y: i16) bool {
        for (self.elements[0..self.len]) |*element| switch (element.*) {
            .focus_frame => |*frame| if (frame.id == id) {
                frame.focus_offset_x = offset_x;
                frame.focus_offset_y = offset_y;
                return true;
            },
            .menu_row => |*row| if (row.id == id) {
                row.focus_offset_x = offset_x;
                row.focus_offset_y = offset_y;
                return true;
            },
            .action_card => |*card| if (card.id == id) {
                card.focus_offset_x = offset_x;
                card.focus_offset_y = offset_y;
                return true;
            },
            .overlay_row => |*row| if (row.id == id) {
                row.focus_offset_x = offset_x;
                row.focus_offset_y = offset_y;
                return true;
            },
            .cartridge => |*item| if (item.id == id) {
                item.focus_offset_x = offset_x;
                item.focus_offset_y = offset_y;
                return true;
            },
            .keyboard => |*item| if (item.id == id) {
                item.focus_offset_x = offset_x;
                item.focus_offset_y = offset_y;
                return true;
            },
            else => {},
        };
        return false;
    }

    /// Cards can change emphasis across a spatial layout. Morph the shared
    /// focus plate instead of snapping its size at the new destination.
    pub fn setFocusSizeOffset(self: *Tree, id: interaction.Id, width_delta: i16, height_delta: i16) bool {
        for (self.elements[0..self.len]) |*element| switch (element.*) {
            .action_card => |*card| if (card.id == id) {
                card.focus_width_delta = width_delta;
                card.focus_height_delta = height_delta;
                return true;
            },
            else => {},
        };
        return false;
    }

    pub fn meterValue(self: *const Tree, id: interaction.Id) ?u16 {
        for (self.slice()) |element| if (element == .meter and element.meter.id == id)
            return element.meter.value;
        return null;
    }

    pub fn setMeterValue(self: *Tree, id: interaction.Id, value: u16) bool {
        for (self.elements[0..self.len]) |*element| if (element.* == .meter and element.meter.id == id) {
            element.meter.value = @min(1000, value);
            return true;
        };
        return false;
    }

    pub fn hasActivity(self: *const Tree) bool {
        for (self.slice()) |element| switch (element) {
            .activity => return true,
            .focus_frame => |value| if (value.state == .busy) return true,
            .menu_row => |value| if (value.state == .busy) return true,
            .action_card => |value| if (value.state == .busy) return true,
            .overlay_row => |value| if (value.state == .busy) return true,
            else => {},
        };
        return false;
    }

    pub fn setActivityPhase(self: *Tree, phase: u16, animated: bool) void {
        for (self.elements[0..self.len]) |*element| switch (element.*) {
            .activity => |*value| {
                value.phase = phase % 1000;
                value.animated = animated;
            },
            .focus_frame => |*value| if (value.state == .busy) {
                value.activity_phase = phase % 1000;
                value.activity_animated = animated;
            },
            .menu_row => |*value| if (value.state == .busy) {
                value.activity_phase = phase % 1000;
                value.activity_animated = animated;
            },
            .action_card => |*value| if (value.state == .busy) {
                value.activity_phase = phase % 1000;
                value.activity_animated = animated;
            },
            .overlay_row => |*value| if (value.state == .busy) {
                value.activity_phase = phase % 1000;
                value.activity_animated = animated;
            },
            else => {},
        };
    }

    /// Translate a complete declarative scene for shared page motion. Scene
    /// builders keep authoring settled geometry; the transition controller is
    /// the only caller that offsets it during composition.
    pub fn translateX(self: *Tree, offset_x: i16) void {
        for (self.elements[0..self.len]) |*element| switch (element.*) {
            inline else => |*value| value.bounds.x = @intCast(std.math.clamp(
                @as(i32, value.bounds.x) + offset_x,
                0,
                std.math.maxInt(u16),
            )),
        };
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

test "meter values are addressable by stable identity and clamped" {
    const theme = @import("theme.zig").light;
    const id = interaction.Id.scoped(.brightness_meter, 0);
    var tree = Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .meter = .{ .id = id, .bounds = .{ .x = 10, .y = 10, .width = 200, .height = 40 }, .value = 400, .track = theme.surface, .fill = theme.text, .thumb = theme.accent } });
    try std.testing.expectEqual(@as(u16, 400), tree.meterValue(id).?);
    try std.testing.expect(tree.setMeterValue(id, 1200));
    try std.testing.expectEqual(@as(u16, 1000), tree.meterValue(id).?);
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
    try std.testing.expect(tree.setFocusOffset(id, 12, -20));
    try std.testing.expectEqual(@as(i16, 12), tree.elements[0].menu_row.focus_offset_x);
    try std.testing.expectEqual(@as(i16, -20), tree.elements[0].menu_row.focus_offset_y);
}

test "complete scenes can be translated without screen-specific geometry" {
    const theme = @import("theme.zig").light;
    var tree = Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .text = .{ .bounds = .{ .x = 48, .y = 40, .width = 300, .height = 60 }, .value = "Games", .color = theme.text } });
    tree.add(.{ .menu_row = .{ .bounds = .{ .x = 28, .y = 138, .width = 968, .height = 94 }, .label = "Recent" } });
    tree.translateX(-24);
    try std.testing.expectEqual(@as(u16, 24), tree.elements[0].text.bounds.x);
    try std.testing.expectEqual(@as(u16, 4), tree.elements[1].menu_row.bounds.x);
    tree.translateX(24);
    try std.testing.expectEqual(@as(u16, 48), tree.elements[0].text.bounds.x);
    try std.testing.expectEqual(@as(u16, 28), tree.elements[1].menu_row.bounds.x);
}

test "semantic action states own distinct styling and shared activity" {
    const theme = @import("theme.zig").light;
    const id = interaction.Id.scoped(.settings, 2);
    var tree = Tree{ .theme = theme, .background = theme.background };
    tree.add(.{ .menu_row = .{ .id = id, .state = .focused, .bounds = .{ .x = 0, .y = 0, .width = 400, .height = 88 }, .label = "Apply" } });
    try std.testing.expect(tree.setInteraction(id, .busy));
    try std.testing.expect(tree.hasActivity());
    tree.setActivityPhase(740, false);
    try std.testing.expectEqual(@as(u16, 740), tree.elements[0].menu_row.activity_phase);
    try std.testing.expect(!tree.elements[0].menu_row.activity_animated);
    try std.testing.expect(tree.setInteraction(id, .failed));
    try std.testing.expect(!tree.hasActivity());
    try std.testing.expectEqual(theme.danger, tree.elements[0].menu_row.style.accent);
    try std.testing.expectEqual(@as(u16, 54), stateAffordanceWidth(.failed));
    try std.testing.expectEqual(@as(u16, 0), stateAffordanceWidth(.focused));
}

test "tiles and cartridges share press state with rows" {
    const theme = @import("theme.zig").light;
    const tile_id = interaction.Id.scoped(.library, 2);
    var tile = Tree{ .theme = theme, .background = theme.background };
    tile.add(.{ .focus_frame = .{ .id = tile_id, .state = .focused, .bounds = .{ .x = 20, .y = 40, .width = 100, .height = 80 } } });
    try std.testing.expectEqual(tile_id, tile.focusedId().?);
    try std.testing.expect(tile.setInteraction(tile_id, .pressed));
    try std.testing.expectEqual(interaction.State.pressed, tile.elements[0].focus_frame.state);

    const shelf_id = interaction.Id.scoped(.library, 4);
    var shelf = Tree{ .theme = theme, .background = theme.background };
    shelf.add(.{ .cartridge = .{ .id = shelf_id, .state = .focused, .bounds = .{ .x = 200, .y = 100, .width = 200, .height = 300 }, .platform = "nes", .texture = null, .sprite = null } });
    try std.testing.expectEqual(shelf_id, shelf.focusedId().?);
    try std.testing.expect(shelf.setInteraction(shelf_id, .pressed));
    try std.testing.expectEqual(interaction.State.pressed, shelf.elements[0].cartridge.state);
}
