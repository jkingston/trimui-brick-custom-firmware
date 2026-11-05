// SPDX-License-Identifier: GPL-2.0-only
// Shared compile-time design rules. Appearance changes colours, never geometry.
pub const Weight = enum { regular, medium, semibold };
pub const Alignment = enum { start, center, end };
pub const Font = struct {
    size: u16,
    weight: Weight = .regular,
    // Zero preserves the font's natural metrics, including script fallback.
    line_height: u16 = 0,
    alignment: Alignment = .start,
};
pub const Typography = struct { title: Font, body: Font, caption: Font, control: Font, brand: Font };
pub const Spacing = struct { small: u16, medium: u16, large: u16, margin: u16 };
pub const Geometry = struct {
    width: u16,
    height: u16,
    rule: u16,
    focus: u16,
    header_y: u16,
    header_rule_y: u16,
    footer_y: u16,
    row_padding: u16,
    row_text_y: u16,
    row_detail_y: u16,
    home_top: u16,
    home_step: u16,
    home_height: u16,
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
    grid_columns: u16,
    grid_rows: u16,
    radius: u16,
    glyph_size: u16,
    hint_gap: u16,
};
pub const Easing = enum { quadratic_out };
pub const Motion = struct { duration_ms: u16, frame_ms: u16, easing: Easing, reduced: bool = false };
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
        if (self.geometry.overlay_x + self.geometry.overlay_width > self.geometry.width or
            self.geometry.overlay_y + self.geometry.overlay_height > self.geometry.height)
            @compileError("Overlay is outside the screen");
        if (self.motion.duration_ms == 0 or self.motion.frame_ms == 0)
            @compileError("Invalid motion timing");
    }
};
pub const config = Config{
    .typography = .{
        .title = .{ .size = 40, .weight = .semibold },
        .body = .{ .size = 36 },
        .caption = .{ .size = 28 },
        .control = .{ .size = 28 },
        .brand = .{ .size = 60, .weight = .semibold },
    },
    .spacing = .{ .small = 8, .medium = 16, .large = 24, .margin = 40 },
    .geometry = .{
        .width = 1024,
        .height = 768,
        .rule = 2,
        .focus = 6,
        .header_y = 24,
        .header_rule_y = 100,
        .footer_y = 704,
        .row_padding = 24,
        .row_text_y = 22,
        .row_detail_y = 50,
        .home_top = 140,
        .home_step = 104,
        .home_height = 92,
        .settings_top = 112,
        .settings_step = 108,
        .settings_height = 100,
        .overlay_x = 168,
        .overlay_y = 40,
        .overlay_width = 688,
        .overlay_height = 688,
        .overlay_row_top = 208,
        .overlay_row_step = 84,
        .overlay_row_height = 76,
        .grid_columns = 3,
        .grid_rows = 2,
        .radius = 12,
        .glyph_size = 40,
        .hint_gap = 16,
    },
    .motion = .{ .duration_ms = 150, .frame_ms = 16, .easing = .quadratic_out },
};
comptime {
    config.validate();
}
pub const typeface = config.typography;
pub const spacing = config.spacing;
pub const geometry = config.geometry;
pub const motion = config.motion;
