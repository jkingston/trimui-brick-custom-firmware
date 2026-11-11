// SPDX-License-Identifier: GPL-2.0-only
const bluetooth_model = @import("bluetooth.zig");
const components = @import("ui_components.zig");
const design = @import("design.zig");
const font = design.typeface;
const geometry = design.geometry;
const interaction = @import("interaction.zig");
const scene = @import("ui_scene.zig");

const Theme = scene.Theme;
const Tree = scene.Tree;

pub fn list(theme: Theme, state: *const bluetooth_model.Model) Tree {
    const snapshot = &state.snapshot;
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, "Bluetooth");
    result.add(.{ .overlay_row = .{
        .id = interaction.Id.scoped(.bluetooth_list, 0),
        .bounds = .{ .x = 28, .y = 116, .width = 968, .height = 92 },
        .label = "Bluetooth",
        .detail = "",
        .value = if (!state.initialized) "Checking…" else switch (snapshot.radio) {
            .off => "Off",
            .stopping => "Stopping…",
            .unavailable => "Unavailable",
            .failed => "Failed",
            .starting => "Starting…",
            .ready => "On",
        },
        .selected = state.selected == 0,
        .disclosure = false,
    } });
    components.text(&result, .{ .x = 48, .y = 218, .width = 928, .height = 40 }, state.status(), if (snapshot.radio == .failed or snapshot.discovery == .failed) theme.text else theme.muted, font.caption);

    if (!state.initialized) {
        components.text(&result, .{ .x = 48, .y = 318, .width = 864, .height = 112 }, "Waiting for the Bluetooth service to start.", theme.text, font.body);
    } else if (snapshot.radio == .ready) {
        const visible: usize = 3;
        const first = @min(state.selected -| 2, @as(usize, snapshot.device_count + 1) -| visible);
        const total = snapshot.device_count + 1;
        for (0..@min(visible, total - first)) |row| {
            const item = first + row;
            if (item == snapshot.device_count) {
                result.add(.{ .overlay_row = .{
                    .id = interaction.Id.scoped(.bluetooth_list, item + 1),
                    .bounds = .{ .x = 28, .y = 258 + @as(u16, @intCast(row)) * 108, .width = 968, .height = components.single_row_height },
                    .label = if (snapshot.discovery == .idle) "Find devices" else "Stop searching",
                    .detail = "",
                    .selected = state.selected == item + 1,
                    .disclosure = false,
                } });
                continue;
            }
            const device = &snapshot.devices[item];
            const operating = snapshot.operation_device.len != 0 and bluetooth_model.Identity.eql(snapshot.operation_device, device.id);
            result.add(.{ .overlay_row = .{
                .id = interaction.Id.scoped(.bluetooth_list, item + 1),
                .bounds = .{ .x = 28, .y = 258 + @as(u16, @intCast(row)) * 108, .width = 968, .height = components.supporting_row_height },
                .label = device.name.slice(),
                .detail = if (operating) switch (snapshot.operation) {
                    .pairing => "Pairing…",
                    .connection => "Connecting…",
                    .disconnection => "Disconnecting…",
                    .forget => "Forgetting…",
                    else => device.detail(),
                } else device.detail(),
                .value = device.battery_label.slice(),
                .selected = state.selected == item + 1,
                .disclosure = device.state == .connected or device.state == .preparing_audio or device.state == .ready,
            } });
        }
        components.continuation(&result, 258, 582, first != 0, first + visible < total);
    } else if (snapshot.radio == .off) {
        components.text(&result, .{ .x = 48, .y = 318, .width = 864, .height = 112 }, "Turn Bluetooth on to connect devices.", theme.text, font.body);
    } else if (snapshot.radio == .unavailable) {
        components.text(&result, .{ .x = 48, .y = 318, .width = 864, .height = 112 }, "Bluetooth is unavailable on this device.", theme.text, font.body);
    } else if (snapshot.radio == .failed) {
        components.text(&result, .{ .x = 48, .y = 318, .width = 864, .height = 112 }, "Try again. If it still fails, restart the device.", theme.text, font.body);
    }
    if (snapshot.operation != .none and snapshot.operation != .discovery)
        components.footer(&result, &.{.{ .control = .back, .label = "Cancel" }})
    else if (snapshot.radio == .ready)
        components.footer(&result, &.{ .{ .control = .back, .label = "Settings" }, .{ .control = .filter, .label = if (snapshot.discovery == .idle) "Find" else "Stop" }, .{ .control = .confirm, .label = "Select" } })
    else if (!state.initialized or snapshot.radio == .unavailable)
        components.footer(&result, &.{.{ .control = .back, .label = "Settings" }})
    else
        components.footer(&result, &.{ .{ .control = .back, .label = "Settings" }, .{ .control = .confirm, .label = switch (snapshot.radio) {
            .off => "Turn on",
            .failed => "Retry",
            .starting, .stopping => "Cancel",
            else => "Change",
        } } });
    return result;
}

pub fn details(theme: Theme, state: *const bluetooth_model.Model) Tree {
    const device = state.activeDevice() orelse return list(theme, state);
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, device.name.slice());
    const audio = device.kind == .audio and device.state == .ready;
    const labels = if (audio) [_][]const u8{ if (device.state == .saved) "Connect" else "Disconnect", "Use for game audio", "Forget device" } else [_][]const u8{ if (device.state == .saved) "Connect" else "Disconnect", "Forget device", "" };
    const count: usize = if (audio) 3 else 2;
    for (labels[0..count], 0..) |label, index| result.add(.{ .overlay_row = .{
        .bounds = .{ .x = 28, .y = 148 + @as(u16, @intCast(index)) * 112, .width = 968, .height = components.supporting_row_height },
        .label = label,
        .detail = if (index == 0) device.detail() else "",
        .selected = state.detail_selected == index,
        .disclosure = index + 1 == count,
    } });
    components.footer(&result, &.{ .{ .control = .back, .label = "Bluetooth" }, .{ .control = .confirm, .label = "Select" } });
    return result;
}

pub fn code(theme: Theme, state: *const bluetooth_model.Model) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, "Pair device");
    components.text(&result, .{ .x = 48, .y = 112, .width = 928, .height = 42 }, if (state.snapshot.prompt == .pin) "Enter the device PIN" else "Enter the pairing code", theme.muted, font.caption);
    result.add(.{ .bar = .{ .bounds = .{ .x = 48, .y = 166, .width = 928, .height = 72 }, .color = theme.surface, .radius = geometry.radius } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 178, .width = 880, .height = 48 }, .value = state.field.slice(), .color = theme.text, .font = font.body } });
    result.add(.{ .keyboard = .{ .bounds = .{ .x = 48, .y = 260, .width = 928, .height = 328 }, .selected = state.field.selected } });
    components.footer(&result, &.{ .{ .control = .back, .label = "Cancel" }, .{ .control = .confirm, .label = if (state.field.selected == 39) "Pair" else "Type" } });
    return result;
}

pub fn displayCode(theme: Theme, state: *const bluetooth_model.Model) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, "Pair device");
    var large = font.brand;
    large.alignment = .center;
    large.size = 96;
    large.line_height = 120;
    components.text(&result, .{ .x = 80, .y = 238, .width = 864, .height = 120 }, state.snapshot.prompt_value[0..state.snapshot.prompt_value_len], theme.text, large);
    var note_font = font.caption;
    note_font.alignment = .center;
    components.text(&result, .{ .x = 80, .y = 392, .width = 864, .height = 84 }, "Enter this code on the other device.", theme.muted, note_font);
    components.footer(&result, &.{.{ .control = .back, .label = "Cancel" }});
    return result;
}
