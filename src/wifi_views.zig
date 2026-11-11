// SPDX-License-Identifier: GPL-2.0-only
const components = @import("ui_components.zig");
const design = @import("design.zig");
const font = design.typeface;
const geometry = design.geometry;
const interaction = @import("interaction.zig");
const scene = @import("ui_scene.zig");
const wifi_model = @import("wifi.zig");

const Theme = scene.Theme;
const Tree = scene.Tree;

pub fn wifi(theme: Theme, selected: usize, status: []const u8, primary: []const u8, has_url: bool) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, "Wi-Fi sign in");
    result.add(.{ .text = .{ .bounds = .{ .x = 48, .y = 116, .width = 928, .height = 52 }, .value = status, .color = theme.muted, .font = font.caption } });
    const labels = [_][]const u8{ primary, "Manual URL and QR" };
    const details = [_][]const u8{ "", if (has_url) "Open on another device" else "Portal URL unavailable" };
    for (labels, details, 0..) |label, detail, index| result.add(.{ .overlay_row = .{
        .bounds = .{ .x = 28, .y = 210 + @as(u16, @intCast(index)) * 112, .width = 968, .height = 104 },
        .label = label,
        .detail = detail,
        .selected = selected == index,
        .disclosure = index == 1 and has_url,
    } });
    components.footer(&result, &.{ .{ .control = .back, .label = "Settings" }, .{ .control = .confirm, .label = "Select" } });
    return result;
}

pub fn wifiFallback(theme: Theme, url: []const u8, qr: *const @import("captive.zig").Qr) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, "Open on your phone");
    if (qr.width != 0) result.add(.{ .qr_code = .{
        .bounds = .{ .x = 334, .y = 126, .width = 356, .height = 356 },
        .cells = qr.cells[0 .. @as(usize, qr.width) * qr.width],
        .width = qr.width,
        .foreground = .{ .r = 0, .g = 0, .b = 0 },
        .background = .{ .r = 255, .g = 255, .b = 255 },
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 64, .y = 512, .width = 896, .height = 96 }, .value = url, .color = theme.text, .font = font.caption, .lines = 2 } });
    components.footer(&result, &.{.{ .control = .back, .label = "Wi-Fi" }});
    return result;
}

fn wifiSecurity(security: wifi_model.Security) []const u8 {
    return switch (security) {
        .open => "Open network",
        .wpa2_personal => "Secured",
        .unsupported => "Unsupported",
    };
}

fn wifiValue(network: *const wifi_model.Network) []const u8 {
    return switch (network.security) {
        .open => switch (network.signal) {
            .weak => "Weak · Open",
            .fair => "Fair · Open",
            .good => "Good · Open",
            .strong => "Strong · Open",
        },
        .wpa2_personal => switch (network.signal) {
            .weak => "Weak · Secured",
            .fair => "Fair · Secured",
            .good => "Good · Secured",
            .strong => "Strong · Secured",
        },
        .unsupported => "Unsupported",
    };
}

pub fn wifiPicker(theme: Theme, state: *const wifi_model.Model) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, "Wi-Fi");
    result.add(.{ .overlay_row = .{
        .id = interaction.Id.scoped(.wifi_list, 0),
        .bounds = .{ .x = 28, .y = 116, .width = 968, .height = 92 },
        .label = "Wi-Fi",
        .detail = "",
        .value = if (!state.initialized) "Checking…" else switch (state.snapshot.radio) {
            .off => "Off",
            .stopping => "Stopping…",
            .starting => "Starting…",
            .ready => "On",
            .unavailable => "Unavailable",
            .failed => "Failed",
        },
        .selected = state.selected == 0,
        .disclosure = false,
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 48, .y = 218, .width = 928, .height = 40 }, .value = state.status(), .color = theme.muted, .font = font.caption } });

    const visible: usize = 3;
    const total = state.itemCount() - 1;
    const logical = state.selected -| 1;
    const first: usize = @min(logical -| 2, total -| visible);
    for (0..@min(visible, total - first)) |row_index| {
        const item = first + row_index;
        const y: u16 = 258 + @as(u16, @intCast(row_index)) * 108;
        if (item < state.snapshot.network_count) {
            const network = &state.snapshot.networks[item];
            result.add(.{ .overlay_row = .{
                .id = interaction.Id.scoped(.wifi_list, item + 1),
                .bounds = .{ .x = 28, .y = y, .width = 968, .height = components.supporting_row_height },
                .label = network.name.slice(),
                .detail = wifi_model.stateDetail(network.state),
                .value = wifiValue(network),
                .selected = state.selected == item + 1,
                .disclosure = network.state != .saved and network.state != .out_of_range,
            } });
        } else if (item == state.snapshot.network_count) {
            result.add(.{ .overlay_row = .{
                .id = interaction.Id.scoped(.wifi_list, item + 1),
                .bounds = .{ .x = 28, .y = y, .width = 968, .height = components.single_row_height },
                .label = "Add hidden network",
                .detail = "",
                .selected = state.selected == item + 1,
            } });
        }
    }
    components.continuation(&result, 258, 582, first != 0, first + visible < total);
    if (!state.initialized)
        components.text(&result, .{ .x = 48, .y = 318, .width = 864, .height = 112 }, "Waiting for the Wi-Fi service to start.", theme.text, font.body)
    else if (state.snapshot.radio == .off)
        components.text(&result, .{ .x = 48, .y = 318, .width = 864, .height = 112 }, "Turn Wi-Fi on to find and connect to networks.", theme.text, font.body)
    else if (state.snapshot.radio == .unavailable)
        components.text(&result, .{ .x = 48, .y = 318, .width = 864, .height = 112 }, "Wi-Fi is unavailable on this device.", theme.text, font.body)
    else if (state.snapshot.radio == .failed)
        components.text(&result, .{ .x = 48, .y = 318, .width = 864, .height = 112 }, "Try again. If it still fails, restart the device.", theme.text, font.body);
    var controls = [_]components.Hint{ .{ .control = .back, .label = "Settings" }, .{ .control = .confirm, .label = if (state.selected == 0) switch (state.snapshot.radio) {
        .off => "Turn on",
        .failed => "Retry",
        else => "Turn off",
    } else "Open" }, .{ .control = .filter, .label = "Refresh" } };
    const actionable = state.initialized and state.snapshot.radio != .unavailable and state.snapshot.radio != .stopping;
    components.footer(&result, controls[0..if (state.snapshot.can_scan) 3 else if (actionable) 2 else 1]);
    return result;
}

pub fn wifiNetworkDetails(theme: Theme, network: *const wifi_model.Network, selected: usize) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, network.name.slice());
    const primary = switch (network.state) {
        .sign_in => "Sign in",
        .limited => "Retry connection check",
        .connected => "Disconnect",
        .connecting, .validating, .reconnecting => "Cancel",
        .auth_failed => "Edit password",
        else => "Connect",
    };
    const labels = [_][]const u8{ primary, "Auto-connect", "Private address", "Connection info", "Forget network" };
    const values = [_][]const u8{ "", if (network.auto_connect) "On" else "Off", if (network.private_address) "On" else "Off", wifiSecurity(network.security), "" };
    const first: usize = @min(selected -| 2, labels.len - 4);
    for (labels[first .. first + 4], values[first .. first + 4], first..) |label, value, index| result.add(.{ .overlay_row = .{
        .id = interaction.Id.scoped(.wifi_details, index),
        .bounds = .{ .x = 28, .y = 144 + @as(u16, @intCast(index - first)) * 112, .width = 968, .height = 104 },
        .label = label,
        .detail = if (index == 0) wifi_model.stateDetail(network.state) else if (index == 2) "Recommended" else "",
        .value = value,
        .selected = index == selected,
        .disclosure = index == 3 or index == 4,
    } });
    components.continuation(&result, 144, 592, first != 0, first + 4 < labels.len);
    if (network.state == .sign_in)
        components.footer(&result, &.{ .{ .control = .back, .label = "Wi-Fi" }, .{ .control = .view, .label = "Sign-in address" }, .{ .control = .confirm, .label = "Select" } })
    else
        components.footer(&result, &.{ .{ .control = .back, .label = "Wi-Fi" }, .{ .control = .confirm, .label = "Select" } });
    return result;
}

pub fn wifiPassword(theme: Theme, network_name: []const u8, selected_key: u8, password: []const u8, show: bool) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, network_name);
    result.add(.{ .text = .{ .bounds = .{ .x = 48, .y = 112, .width = 928, .height = 42 }, .value = "Enter the Wi-Fi password", .color = theme.muted, .font = font.caption } });
    const mask = "************************************************************************************************";
    const count = @min(password.len, mask.len);
    result.add(.{ .bar = .{ .bounds = .{ .x = 48, .y = 166, .width = 928, .height = 72 }, .color = theme.surface, .radius = geometry.radius } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 178, .width = 880, .height = 48 }, .value = if (show) password[0..count] else mask[0..count], .color = theme.text, .font = font.body } });
    result.add(.{ .keyboard = .{ .bounds = .{ .x = 48, .y = 260, .width = 928, .height = 328 }, .selected = selected_key } });
    components.footer(&result, &.{ .{ .control = .back, .label = "Cancel" }, .{ .control = .view, .label = if (show) "Hide" else "Show" }, .{ .control = .confirm, .label = if (selected_key == 39) "Connect" else "Type" } });
    return result;
}

pub fn wifiHiddenName(theme: Theme, selected_key: u8, name: []const u8) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, "Hidden network");
    result.add(.{ .text = .{ .bounds = .{ .x = 48, .y = 112, .width = 928, .height = 42 }, .value = "Enter the exact network name", .color = theme.muted, .font = font.caption } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 48, .y = 166, .width = 928, .height = 72 }, .color = theme.surface, .radius = geometry.radius } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 178, .width = 880, .height = 48 }, .value = name, .color = theme.text, .font = font.body } });
    result.add(.{ .keyboard = .{ .bounds = .{ .x = 48, .y = 260, .width = 928, .height = 328 }, .selected = selected_key } });
    components.footer(&result, &.{ .{ .control = .back, .label = "Cancel" }, .{ .control = .confirm, .label = if (selected_key == 39) "Continue" else "Type" } });
    return result;
}

pub fn wifiConnectionInfo(theme: Theme, network: *const wifi_model.Network) Tree {
    var result = Tree{ .theme = theme, .background = theme.background };
    components.header(&result, "Connection info");
    const signal = switch (network.signal) {
        .weak => "Weak",
        .fair => "Fair",
        .good => "Good",
        .strong => "Strong",
    };
    const labels = [_][]const u8{ "Network", "Security", "Signal", "IP address" };
    const values = [_][]const u8{ network.name.slice(), wifiSecurity(network.security), signal, if (network.address.len == 0) "Not assigned" else network.address.slice() };
    for (labels, values, 0..) |label, value, index| result.add(.{ .overlay_row = .{
        .bounds = .{ .x = 28, .y = 144 + @as(u16, @intCast(index)) * 112, .width = 968, .height = 104 },
        .label = label,
        .detail = "",
        .value = value,
        .selected = false,
        .disclosure = false,
    } });
    components.footer(&result, &.{.{ .control = .back, .label = "Network" }});
    return result;
}
