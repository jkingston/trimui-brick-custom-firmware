// SPDX-License-Identifier: GPL-2.0-only
const ui = @import("ui.zig");

pub const Action = enum { up, down, select, back, menu };

const main_items = [_][]const u8{ "SYSTEM", "SETTINGS" };
const settings_items = [_][]const u8{ "DISPLAY", "AUDIO", "NETWORK", "POWER", "ABOUT" };

pub const Page = enum { main, settings };

pub const Model = struct {
    page: Page = .main,
    selected: usize = 0,
    revision: u64 = 1,

    pub fn apply(self: *Model, action: Action) bool {
        const count = self.itemCount();
        const before = self.*;
        switch (action) {
            .up => self.selected = if (self.selected == 0) count - 1 else self.selected - 1,
            .down => self.selected = (self.selected + 1) % count,
            .select => if (self.page == .main and self.selected == 1) {
                self.page = .settings;
                self.selected = 0;
            },
            .back => if (self.page != .main) {
                self.page = .main;
                self.selected = 1;
            },
            .menu => {
                self.page = .main;
                self.selected = 0;
            },
        }
        const changed = before.page != self.page or before.selected != self.selected;
        if (changed) self.revision += 1;
        return changed;
    }

    fn itemCount(self: *const Model) usize {
        return switch (self.page) {
            .main => main_items.len,
            .settings => settings_items.len,
        };
    }

    pub fn tree(self: *const Model) ui.Tree {
        return switch (self.page) {
            .main => (ui.Menu{ .title = "BRICK", .items = &main_items, .selected = self.selected }).tree(),
            .settings => (ui.Menu{ .title = "SETTINGS", .items = &settings_items, .selected = self.selected }).tree(),
        };
    }
};

test "navigation wraps and enters settings" {
    const testing = @import("std").testing;
    var model = Model{};
    try testing.expect(model.apply(.up));
    try testing.expectEqual(@as(usize, 1), model.selected);
    try testing.expect(model.apply(.select));
    try testing.expectEqual(Page.settings, model.page);
    try testing.expect(model.apply(.back));
    try testing.expectEqual(Page.main, model.page);
}
