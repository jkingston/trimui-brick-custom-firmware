// SPDX-License-Identifier: GPL-2.0-only
// Shared compile-time design rules. Appearance changes colours, never geometry.
pub const Weight = enum { regular, medium, semibold };
pub const Family = enum { ui, display };
pub const Alignment = enum { start, center, end };
pub const Font = struct {
    size: u16,
    weight: Weight = .regular,
    family: Family = .ui,
    // Zero preserves the font's natural metrics, including script fallback.
    line_height: u16 = 0,
    alignment: Alignment = .start,
    // Centre visible glyphs within the line box for menu controls.
    ink_centered: bool = false,
};
pub const Typography = struct {
    title: Font,
    body: Font,
    caption: Font,
    control: Font,
    brand: Font,
    editorial_control: Font,
    editorial_compact: Font,
    editorial_row: Font,
    editorial_action: Font,
};
pub const Spacing = struct { small: u16, medium: u16, large: u16, margin: u16 };
pub const Geometry = struct {
    width: u16,
    height: u16,
    rule: u16,
    focus: u16,
    header_y: u16,
    header_rule_y: u16,
    feedback_y: u16,
    feedback_height: u16,
    footer_rule_y: u16,
    footer_y: u16,
    footer_height: u16,
    row_padding: u16,
    row_text_y: u16,
    row_detail_y: u16,
    settings_top: u16,
    settings_step: u16,
    settings_height: u16,
    overlay_x: u16,
    overlay_y: u16,
    overlay_width: u16,
    overlay_height: u16,
    overlay_row_top: u16,
    overlay_row_step: u16,
    overlay_row_height: u16,
    shelf_step: u16,
    grid_columns: u16,
    grid_rows: u16,
    radius: u16,
    glyph_size: u16,
    hint_gap: u16,
};
/// Curves describe intent rather than a component implementation. Spatial
/// entrances settle, exits get out of the way, and effect changes remain
/// neutral. Components must use a semantic MotionRole instead of inventing a
/// duration or curve locally.
pub const Easing = enum { standard, accelerate, decelerate };
pub const Motion = struct { duration_ms: u16, frame_ms: u16, easing: Easing, reduced: bool = false };
pub const MotionRole = enum { press, focus, content, enter, exit, feedback };
pub const MotionTokens = struct {
    press: Motion,
    focus: Motion,
    content: Motion,
    enter: Motion,
    exit: Motion,
    feedback: Motion,

    pub fn get(self: MotionTokens, role: MotionRole) Motion {
        return switch (role) {
            inline else => |tag| @field(self, @tagName(tag)),
        };
    }

    pub fn validate(comptime self: MotionTokens) void {
        inline for (@typeInfo(MotionTokens).@"struct".field_names) |name| {
            const token = @field(self, name);
            if (token.duration_ms == 0 or token.frame_ms == 0)
                @compileError("Invalid motion timing");
        }
    }
};

pub const motion_tokens = MotionTokens{
    .press = .{ .duration_ms = 64, .frame_ms = 16, .easing = .standard },
    .focus = .{ .duration_ms = 100, .frame_ms = 16, .easing = .decelerate },
    .content = .{ .duration_ms = 150, .frame_ms = 16, .easing = .decelerate },
    .enter = .{ .duration_ms = 167, .frame_ms = 16, .easing = .decelerate },
    .exit = .{ .duration_ms = 120, .frame_ms = 16, .easing = .accelerate },
    .feedback = .{ .duration_ms = 120, .frame_ms = 16, .easing = .standard },
};
pub const Config = struct {
    typography: Typography,
    spacing: Spacing,
    geometry: Geometry,
    motion: Motion,

    pub fn validate(comptime self: Config) void {
        inline for (@typeInfo(Typography).@"struct".field_names) |name| {
            const font = @field(self.typography, name);
            if (font.size == 0 or font.size > 96) @compileError("Invalid font size");
            if (font.line_height != 0 and (font.line_height < font.size or font.line_height > 192))
                @compileError("Invalid line height");
        }
        if (self.geometry.width <= 2 * self.spacing.margin or self.geometry.height <= self.geometry.footer_y)
            @compileError("Invalid screen geometry");
        if (self.geometry.feedback_y + self.geometry.feedback_height >= self.geometry.footer_rule_y or
            self.geometry.footer_rule_y >= self.geometry.footer_y or
            self.geometry.footer_y + self.geometry.footer_height > self.geometry.height)
            @compileError("Invalid feedback and footer bands");
        if (self.geometry.overlay_x + self.geometry.overlay_width > self.geometry.width or
            self.geometry.overlay_y + self.geometry.overlay_height > self.geometry.height)
            @compileError("Overlay is outside the screen");
        if (self.motion.duration_ms == 0 or self.motion.frame_ms == 0)
            @compileError("Invalid motion timing");
    }
};
pub const config = Config{
    .typography = .{
        .title = .{ .size = 41, .weight = .semibold, .family = .display, .line_height = 49 },
        .body = .{ .size = 43, .line_height = 52 },
        .caption = .{ .size = 31, .line_height = 40 },
        .control = .{ .size = 31, .line_height = 40 },
        .brand = .{ .size = 60, .weight = .semibold, .family = .display },
        // Sparse navigation keeps these metrics fixed across focus states.
        .editorial_control = .{ .size = 29, .line_height = 38 },
        .editorial_compact = .{ .size = 27, .line_height = 36 },
        .editorial_row = .{ .size = 33, .line_height = 44 },
        .editorial_action = .{ .size = 34, .line_height = 46 },
    },
    .spacing = .{ .small = 8, .medium = 16, .large = 24, .margin = 48 },
    .geometry = .{
        .width = 1024,
        .height = 768,
        .rule = 2,
        .focus = 6,
        .header_y = 37,
        .header_rule_y = 100,
        // Feedback has a stable band above an independently stable action
        // rail. Screens may leave the band empty, but never borrow it.
        .feedback_y = 617,
        .feedback_height = 50,
        .footer_rule_y = 675,
        .footer_y = 699,
        .footer_height = 44,
        .row_padding = 20,
        .row_text_y = 24,
        .row_detail_y = 50,
        .settings_top = 138,
        .settings_step = 94,
        .settings_height = 94,
        .overlay_x = 0,
        .overlay_y = 0,
        .overlay_width = 1024,
        .overlay_height = 768,
        .overlay_row_top = 176,
        .overlay_row_step = 100,
        .overlay_row_height = 100,
        .shelf_step = 128,
        .grid_columns = 3,
        .grid_rows = 2,
        // A small engineered corner softens interactive plates without turning
        // rows into generic pills or cards.
        .radius = 8,
        .glyph_size = 64,
        .hint_gap = 16,
    },
    // Compatibility token for the existing shelf while reusable components
    // migrate to motion_tokens by semantic role.
    .motion = motion_tokens.content,
};
comptime {
    config.validate();
    motion_tokens.validate();
}
pub const typeface = config.typography;
pub const spacing = config.spacing;
pub const geometry = config.geometry;
pub const motion = config.motion;

test "motion roles encode interaction intent" {
    const std = @import("std");
    try std.testing.expect(motion_tokens.press.duration_ms < motion_tokens.focus.duration_ms);
    try std.testing.expect(motion_tokens.exit.duration_ms < motion_tokens.enter.duration_ms);
    try std.testing.expectEqual(Easing.accelerate, motion_tokens.exit.easing);
    try std.testing.expectEqual(Easing.decelerate, motion_tokens.enter.easing);
}
