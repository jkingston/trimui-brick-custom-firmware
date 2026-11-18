// SPDX-License-Identifier: GPL-2.0-only
//! Product-level shell hierarchy. Feature state may change independently, but
//! every renderer and input loop must agree on forward versus return travel.
const input = @import("input.zig");

pub const Page = enum { foyer, games, game, game_details, artwork_identity, artwork_title, artwork_library, artwork_unmatched, settings, setting, wifi, wifi_fallback, bluetooth, systems, views, power, power_confirm };

/// A page is part of one product layer. This keeps shell chrome and hardware
/// buttons tied to the job of a surface instead of to its visual composition.
pub const SurfaceRole = enum {
    exceptional_entry,
    library_home,
    launch,
    device,
    focused_task,
    commitment,
};

pub const MenuBehavior = enum { reveal_device, dismiss_to_library };

pub const ChromePolicy = struct {
    role: SurfaceRole,
    ambient_status: bool,
    menu: MenuBehavior,
};

pub fn chrome(page: Page) ChromePolicy {
    return switch (page) {
        .foyer => .{ .role = .exceptional_entry, .ambient_status = true, .menu = .reveal_device },
        .games => .{ .role = .library_home, .ambient_status = true, .menu = .reveal_device },
        .game => .{ .role = .launch, .ambient_status = false, .menu = .dismiss_to_library },
        .game_details, .artwork_identity, .artwork_title, .artwork_unmatched => .{ .role = .focused_task, .ambient_status = true, .menu = .dismiss_to_library },
        .settings, .setting, .artwork_library, .systems, .views, .power => .{ .role = .device, .ambient_status = true, .menu = .dismiss_to_library },
        .power_confirm => .{ .role = .commitment, .ambient_status = true, .menu = .dismiss_to_library },
        .wifi, .wifi_fallback, .bluetooth => .{ .role = .focused_task, .ambient_status = false, .menu = .dismiss_to_library },
    };
}

pub fn menuDestination(page: Page) ?Page {
    return switch (chrome(page).menu) {
        .reveal_device => .settings,
        .dismiss_to_library => .games,
    };
}

pub fn returnsToParent(action: input.Action, from: Page, to: Page) bool {
    if (action == .back) return true;
    const returning = switch (from) {
        .game, .game_details, .systems, .views => to == .games,
        .artwork_identity => to == .game_details,
        .artwork_title => to == .artwork_identity,
        .artwork_unmatched => to == .artwork_library,
        .setting, .wifi, .bluetooth, .artwork_library => to == .settings,
        .wifi_fallback => to == .wifi,
        .power_confirm => to == .power,
        else => false,
    };
    return returning or (action == .menu and to == .games and from != .foyer);
}

test "page hierarchy gives every renderer the same transition direction" {
    const std = @import("std");
    try std.testing.expect(!returnsToParent(.select, .foyer, .settings));
    try std.testing.expect(returnsToParent(.back, .settings, .foyer));
    try std.testing.expect(returnsToParent(.select, .views, .games));
    try std.testing.expect(returnsToParent(.menu, .settings, .games));
    try std.testing.expect(!returnsToParent(.menu, .foyer, .power));
}

test "surface policy makes Library home and keeps task chrome local" {
    const std = @import("std");
    try std.testing.expectEqual(SurfaceRole.library_home, chrome(.games).role);
    try std.testing.expectEqual(Page.settings, menuDestination(.games).?);
    try std.testing.expectEqual(Page.games, menuDestination(.settings).?);
    try std.testing.expectEqual(Page.games, menuDestination(.wifi).?);
    try std.testing.expect(!chrome(.game).ambient_status);
    try std.testing.expect(!chrome(.bluetooth).ambient_status);
}
