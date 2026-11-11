// SPDX-License-Identifier: GPL-2.0-only
//! Product-level shell hierarchy. Feature state may change independently, but
//! every renderer and input loop must agree on forward versus return travel.
const input = @import("input.zig");

pub const Page = enum { foyer, games, game, settings, setting, wifi, wifi_fallback, bluetooth, systems, views, power, power_confirm };

pub fn returnsToParent(action: input.Action, from: Page, to: Page) bool {
    if (action == .back) return true;
    const returning = switch (from) {
        .game, .systems, .views => to == .games,
        .setting, .wifi, .bluetooth => to == .settings,
        .wifi_fallback => to == .wifi,
        .power_confirm => to == .power,
        else => false,
    };
    return returning or (action == .menu and to == .foyer);
}

test "page hierarchy gives every renderer the same transition direction" {
    const std = @import("std");
    try std.testing.expect(!returnsToParent(.select, .foyer, .settings));
    try std.testing.expect(returnsToParent(.back, .settings, .foyer));
    try std.testing.expect(returnsToParent(.select, .views, .games));
    try std.testing.expect(returnsToParent(.menu, .settings, .foyer));
    try std.testing.expect(!returnsToParent(.menu, .foyer, .power));
}
