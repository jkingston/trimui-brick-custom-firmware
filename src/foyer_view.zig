// SPDX-License-Identifier: GPL-2.0-only
//! Exceptional entry surface used only when immediate return to play is not
//! available. Keeping it named and isolated prevents it becoming a dashboard.
const catalog = @import("catalog.zig");
const components = @import("ui_components.zig");
const design = @import("design.zig");
const game_object = @import("game_object.zig");
const scene = @import("ui_scene.zig");

fn displayFont(size: u16, line_height: u16, weight: design.Weight) design.Font {
    return .{ .size = size, .line_height = line_height, .weight = weight, .family = .display };
}

fn uiFont(size: u16, line_height: u16, weight: design.Weight, alignment: design.Alignment) design.Font {
    return .{ .size = size, .line_height = line_height, .weight = weight, .alignment = alignment };
}

pub fn foyer(theme: scene.Theme, selected: usize) scene.Tree {
    return session(theme, selected, null, false);
}

pub fn session(theme: scene.Theme, selected: usize, recent: ?catalog.Game, resumable: bool) scene.Tree {
    var result = scene.Tree{ .theme = theme, .background = theme.background };
    const with_recent = recent != null;
    components.text(&result, .{ .x = 48, .y = 38, .width = 500, .height = 34 }, if (with_recent) "RETURN TO PLAY" else "BRICK", theme.muted, uiFont(22, 30, .semibold, .start));
    const labels = if (with_recent) [_][]const u8{ "Continue", "Library", "Device" } else [_][]const u8{ "Library", "Device", "" };
    const count: usize = if (with_recent) 3 else 2;
    result.add(.{ .text_block = .{
        .bounds = .{ .x = 48, .y = 142, .width = if (with_recent) 510 else 820, .height = 300 },
        .title = if (with_recent) recent.?.title else "Choose a game",
        .detail = if (with_recent) (if (resumable) "Your last session is ready." else "Start the last game again.") else "",
        .color = theme.text,
        .detail_color = theme.muted,
        .title_font = displayFont(if (with_recent) 66 else 78, if (with_recent) 76 else 90, .semibold),
        .detail_font = uiFont(30, 42, .regular, .start),
        .lines = 2,
        .detail_lines = 2,
        .gap = 22,
    } });
    if (recent) |game| game_object.add(&result, game, .{
        .bounds = .{ .x = 652, .y = 126, .width = 296, .height = 356 },
    });

    const action_x = if (with_recent) [_]u16{ 48, 332, 606 } else [_]u16{ 48, 414, 0 };
    const action_width = if (with_recent) [_]u16{ 228, 218, 218 } else [_]u16{ 310, 310, 0 };
    for (labels[0..count], 0..) |label, index| components.editorialChoice(&result, .foyer, index, selected == index, .{
        .label = label,
        .bounds = .{ .x = action_x[index], .y = 552, .width = action_width[index], .height = 62 },
        .focus_bounds = .{ .x = action_x[index], .y = 546, .width = action_width[index], .height = 72 },
        .scale = .action,
    });
    components.footer(&result, &.{.{ .control = .confirm, .label = if (with_recent and selected == 0) (if (resumable) "Resume" else "Play") else "Open" }});
    return result;
}
