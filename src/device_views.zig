// SPDX-License-Identifier: GPL-2.0-only
//! Device-control compositions. These own authored structure while delegating
//! identity, control state, meters, continuation, and footers to components.
const std = @import("std");
const components = @import("ui_components.zig");
const design = @import("design.zig");
const interaction = @import("interaction.zig");
const scene = @import("ui_scene.zig");
const settings_model = @import("settings.zig");

const font = design.typeface;

fn displayFont(size: u16, line_height: u16, weight: design.Weight, alignment: design.Alignment) design.Font {
    return .{ .size = size, .line_height = line_height, .weight = weight, .family = .display, .alignment = alignment };
}

fn uiFont(size: u16, line_height: u16, weight: design.Weight, alignment: design.Alignment) design.Font {
    return .{ .size = size, .line_height = line_height, .weight = weight, .alignment = alignment };
}

fn editorialHeader(result: *scene.Tree, section: []const u8, context: []const u8) void {
    components.text(result, .{ .x = 48, .y = 35, .width = 300, .height = 40 }, section, result.theme.text, uiFont(25, 32, .semibold, .start));
    if (context.len != 0)
        components.text(result, .{ .x = 510, .y = 35, .width = 336, .height = 40 }, context, result.theme.muted, uiFont(25, 32, .regular, .end));
}

pub fn message(theme: scene.Theme, title: []const u8, subject: []const u8, detail: []const u8) scene.Tree {
    var result = scene.Tree{ .theme = theme, .background = theme.background };
    components.header(&result, title);
    var title_font = font.body;
    title_font.size = 50;
    title_font.weight = .medium;
    title_font.line_height = 60;
    var detail_font = font.caption;
    detail_font.size = 35;
    detail_font.line_height = 51;
    result.add(.{ .text_block = .{ .bounds = .{ .x = 48, .y = 223, .width = 900, .height = 268 }, .title = subject, .detail = detail, .color = theme.text, .detail_color = theme.muted, .title_font = title_font, .detail_font = detail_font, .detail_lines = 2, .gap = 31 } });
    return result;
}

pub fn confirmation(theme: scene.Theme, title: []const u8, subject: []const u8, detail: []const u8, action: []const u8, selected: usize) scene.Tree {
    var result = scene.Tree{ .theme = theme, .background = theme.background };
    editorialHeader(&result, "CONFIRM", title);
    result.add(.{ .text_block = .{
        .bounds = .{ .x = 48, .y = 158, .width = 880, .height = 226 },
        .title = subject,
        .detail = detail,
        .color = theme.text,
        .detail_color = theme.muted,
        .title_font = displayFont(53, 63, .semibold, .start),
        .detail_font = uiFont(28, 40, .regular, .start),
        .lines = 2,
        .detail_lines = 2,
        .gap = 22,
    } });
    const labels = [_][]const u8{ "Cancel", action };
    for (labels, 0..) |label, index| {
        const x: u16 = 48 + @as(u16, @intCast(index)) * 470;
        components.editorialChoice(&result, .confirmation, index, selected == index, .{
            .label = label,
            .bounds = .{ .x = x, .y = 486, .width = 410, .height = 74 },
            .focus_bounds = .{ .x = x, .y = 486, .width = 410, .height = 78 },
            .scale = .action,
            .alignment = .center,
        });
    }
    components.footer(&result, &.{ .{ .control = .back, .label = "Cancel" }, .{ .control = .confirm, .label = "Select" } });
    return result;
}

pub fn choice(theme: scene.Theme, title: []const u8, labels: []const []const u8, selected: usize, active: ?usize, note: []const u8, back: []const u8) scene.Tree {
    var result = scene.Tree{ .theme = theme, .background = theme.background };
    editorialHeader(&result, "CONTROL", title);
    const visible = @min(labels.len, if (note.len != 0) @as(usize, 4) else 6);
    const first = @min(selected -| 2, labels.len - visible);
    const bottom: u16 = if (note.len != 0 or std.mem.eql(u8, title, "Appearance")) 530 else 676;
    const step = (bottom - 138) / @as(u16, @intCast(@max(1, visible)));
    for (first..first + visible) |index| {
        const row_y = 138 + @as(u16, @intCast(index - first)) * step;
        components.editorialChoice(&result, .choice, index, selected == index, .{
            .label = labels[index],
            .bounds = .{ .x = 48, .y = row_y, .width = 700, .height = step -| 8 },
            .focus_bounds = .{ .x = 48, .y = row_y, .width = 880, .height = step -| 8 },
            .scale = .row,
        });
        if (active == index)
            components.text(&result, .{ .x = 792, .y = row_y, .width = 136, .height = step -| 8 }, "ACTIVE", theme.accent, uiFont(21, 30, .semibold, .end));
    }
    components.continuation(&result, 138, bottom, first != 0, first + visible < labels.len);
    if (note.len != 0) result.add(.{ .text = .{ .bounds = .{ .x = 48, .y = 538, .width = 928, .height = 88 }, .value = note, .color = theme.muted, .font = font.caption, .lines = 2 } });
    components.footer(&result, &.{ .{ .control = .back, .label = back }, .{ .control = .confirm, .label = "Select" } });
    return result;
}

pub fn setting(item: settings_model.Setting, selected: usize, active: usize, values: settings_model.Values) scene.Tree {
    const theme = values.appearance.colors();
    if (item == .brightness) {
        var result = scene.Tree{ .theme = theme, .background = theme.background };
        components.header(&result, "Brightness");
        components.text(&result, .{ .x = 96, .y = 186, .width = 500, .height = 36 }, "PANEL OUTPUT", theme.accent, uiFont(20, 28, .semibold, .start));
        components.text(&result, .{ .x = 96, .y = 226, .width = 500, .height = 78 }, settings_model.brightnessTone(values.brightness), theme.text, displayFont(62, 72, .semibold, .start));
        components.text(&result, .{ .x = 760, .y = 252, .width = 168, .height = 34 }, settings_model.brightnessStep(values.brightness), theme.muted, uiFont(21, 29, .regular, .end));
        components.steppedMeter(&result, interaction.Id.scoped(.brightness_meter, 0), .{ .x = 96, .y = 342, .width = 832, .height = 48 }, @as(u16, values.brightness) * 100, 11);
        var note_font = font.caption;
        note_font.alignment = .center;
        components.text(&result, .{ .x = 82, .y = 452, .width = 860, .height = 40 }, "Left / right to adjust", theme.muted, note_font);
        components.footer(&result, &.{.{ .control = .back, .label = "Settings" }});
        return result;
    }
    const note: []const u8 = switch (item) {
        .display_timeout => "The device stays awake.",
        .suspend_timeout => "Bluetooth disconnects during sleep.",
        .performance => "Balance response and battery life.",
        .reduced_motion => "Settle movement immediately.",
        else => "",
    };
    return choice(theme, settings_model.title(item), settings_model.labels(item), selected, active, note, "Settings");
}

pub fn settings(selected: usize, values: settings_model.Values, wifi_summary: []const u8, bluetooth_summary: []const u8) scene.Tree {
    const theme = values.appearance.colors();
    const items = [_][]const u8{ "Brightness", "Performance", "Screen off", "Suspend", "Appearance", "Reduced motion", "Wi-Fi", "Bluetooth" };
    const details = [_][]const u8{ settings_model.brightnessTone(values.brightness), values.value(.performance), values.value(.display_timeout), values.value(.suspend_timeout), values.value(.appearance), values.value(.reduced_motion), wifi_summary, bluetooth_summary };
    const groups = [_][]const u8{ "DISPLAY", "SYSTEM", "DISPLAY", "POWER", "INTERFACE", "INTERFACE", "CONNECTION", "CONNECTION" };
    const stage_labels = [_][]const u8{ "PANEL OUTPUT", "POWER MODE", "SCREEN REST", "DEVICE SLEEP", "VISUAL ENVIRONMENT", "MOVEMENT", "NETWORK", "WIRELESS" };
    const descriptions = [_][]const u8{
        "Set the panel output.",
        "Balance speed and battery life.",
        "Choose when the screen rests.",
        "Choose when the device sleeps.",
        "Select the visual environment.",
        "Settle movement immediately.",
        "Join and manage networks.",
        "Pair controllers and audio.",
    };
    var result = scene.Tree{ .theme = theme, .background = theme.background };
    editorialHeader(&result, "DEVICE", groups[selected]);
    const visible: usize = 5;
    const first = @min(selected -| 2, items.len - visible);
    for (items[first .. first + visible], first..) |item, index| {
        const row_y: u16 = 132 + @as(u16, @intCast(index - first)) * 91;
        components.editorialChoice(&result, .settings, index, index == selected, .{
            .label = item,
            .bounds = .{ .x = 48, .y = row_y, .width = 480, .height = 68 },
            .focus_bounds = .{ .x = 48, .y = row_y, .width = 480, .height = 72 },
            .scale = .row,
        });
    }
    components.text(&result, .{ .x = 602, .y = 178, .width = 330, .height = 38 }, stage_labels[selected], theme.accent, uiFont(20, 28, .semibold, .start));
    const brightness_selected = selected == @backingInt(settings_model.Setting.brightness);
    result.add(.{ .text_block = .{
        .bounds = .{ .x = 602, .y = 226, .width = 330, .height = 270 },
        .title = details[selected],
        .detail = descriptions[selected],
        .color = theme.text,
        .detail_color = theme.muted,
        .title_font = displayFont(58, 68, .semibold, .start),
        .detail_font = uiFont(27, 39, .regular, .start),
        .lines = 2,
        .detail_lines = 3,
        .gap = if (brightness_selected) 116 else 26,
    } });
    components.text(&result, .{ .x = 762, .y = 306, .width = 170, .height = 32 }, if (brightness_selected) settings_model.brightnessStep(values.brightness) else "", theme.muted, uiFont(20, 28, .regular, .end));
    components.steppedMeterState(&result, interaction.Id.scoped(.brightness_meter, 0), .{ .x = 602, .y = 350, .width = 330, .height = 36 }, @as(u16, values.brightness) * 100, 11, brightness_selected);
    components.continuation(&result, 132, 587, first != 0, first + visible < items.len);
    components.footer(&result, &.{ .{ .control = .back, .label = "Library" }, .{ .control = .menu, .label = "Power" }, .{ .control = .confirm, .label = "Open" } });
    return result;
}
