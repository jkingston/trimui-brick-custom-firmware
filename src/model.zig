// SPDX-License-Identifier: GPL-2.0-only
const ui = @import("ui.zig");

pub const Action = enum { up, down, left, right, confirm, back, home, switcher, options, favorite };
pub const Page = enum { home, recent, favorites, systems, games, music, podcasts, audiobooks, now_playing, ports, settings, game_detail, switcher, quick_menu };

const home_items = [_]ui.MenuItem{
    .{ .label = "CONTINUE", .detail = "THE DISPOSSESSED - CHAPTER 7" },
    .{ .label = "GAMES", .detail = "RECENT AND LIBRARY" },
    .{ .label = "MUSIC", .detail = "ALBUMS AND PLAYLISTS" },
    .{ .label = "PODCASTS", .detail = "3 NEW EPISODES" },
    .{ .label = "AUDIOBOOKS", .detail = "2 IN PROGRESS" },
    .{ .label = "PORTS", .detail = "NATIVE GAMES" },
    .{ .label = "SETTINGS", .detail = "SYSTEM" },
};
const music_items = [_]ui.MenuItem{
    .{ .label = "NOW PLAYING", .detail = "TEARDROP - MASSIVE ATTACK" }, .{ .label = "ALBUMS", .detail = "128 ALBUMS" },
    .{ .label = "ARTISTS", .detail = "74 ARTISTS" },                    .{ .label = "SONGS", .detail = "1642 SONGS" },
    .{ .label = "PLAYLISTS", .detail = "9 PLAYLISTS" },                 .{ .label = "FOLDERS", .detail = "BROWSE FILES" },
};
const podcast_items = [_]ui.MenuItem{
    .{ .label = "CONTINUE LISTENING", .detail = "THE MEMORY PALACE - 18 MIN LEFT" },
    .{ .label = "NEW EPISODES", .detail = "3 UNPLAYED" },
    .{ .label = "SHOWS", .detail = "14 FOLLOWED" },
    .{ .label = "DOWNLOADS", .detail = "6 EPISODES" },
    .{ .label = "ADD FEED", .detail = "RSS URL OR OPML" },
};
const audiobook_items = [_]ui.MenuItem{
    .{ .label = "CONTINUE LISTENING", .detail = "THE DISPOSSESSED - CHAPTER 7" },
    .{ .label = "BOOKS", .detail = "26 BOOKS" },
    .{ .label = "AUTHORS", .detail = "18 AUTHORS" },
    .{ .label = "COLLECTIONS", .detail = "4 COLLECTIONS" },
    .{ .label = "FOLDERS", .detail = "BROWSE FILES" },
};
const recent_items = [_]ui.MenuItem{
    .{ .label = "METROID ZERO MISSION", .detail = "GAME BOY ADVANCE - 24 MIN" },
    .{ .label = "RIDGE RACER TYPE 4", .detail = "PLAYSTATION - YESTERDAY" },
    .{ .label = "CELESTE", .detail = "PORT - MONDAY" },
    .{ .label = "TETRIS DX", .detail = "GAME BOY COLOR - 6 DAYS" },
};
const favorite_items = [_]ui.MenuItem{
    .{ .label = "CASTLEVANIA ARIA", .detail = "GAME BOY ADVANCE" }, .{ .label = "CHRONO TRIGGER", .detail = "SUPER NINTENDO" },
    .{ .label = "METAL SLUG", .detail = "NEO GEO" },                .{ .label = "OUTRUN 2006", .detail = "PSP" },
};
const system_items = [_]ui.MenuItem{
    .{ .label = "GAME BOY ADVANCE", .detail = "42 GAMES" }, .{ .label = "PLAYSTATION", .detail = "18 GAMES" },
    .{ .label = "SUPER NINTENDO", .detail = "31 GAMES" },   .{ .label = "DREAMCAST", .detail = "7 GAMES" },
    .{ .label = "ALL GAMES", .detail = "184 GAMES" },
};
const game_items = [_]ui.MenuItem{
    .{ .label = "ADVANCE WARS", .detail = "NOT PLAYED" },  .{ .label = "CASTLEVANIA ARIA", .detail = "FAVORITE - 3H 12M" },
    .{ .label = "METROID FUSION", .detail = "1H 48M" },    .{ .label = "METROID ZERO MISSION", .detail = "RESUME - 24M" },
    .{ .label = "WARIOWARE INC", .detail = "NOT PLAYED" },
};
const port_items = [_]ui.MenuItem{
    .{ .label = "CELESTE", .detail = "READY" },                  .{ .label = "CAVE STORY", .detail = "READY" },
    .{ .label = "SHOVEL KNIGHT", .detail = "GAME DATA NEEDED" }, .{ .label = "PORTMASTER", .detail = "BROWSE PORTS" },
};
const setting_items = [_]ui.MenuItem{
    .{ .label = "DISPLAY", .detail = "BRIGHTNESS AND COLOR" }, .{ .label = "SOUND", .detail = "VOLUME AND OUTPUT" },
    .{ .label = "NETWORK", .detail = "WI-FI AND SERVICES" },   .{ .label = "POWER", .detail = "SLEEP AND PERFORMANCE" },
    .{ .label = "STORAGE", .detail = "57 GB FREE" },           .{ .label = "ABOUT", .detail = "SYSTEM INFORMATION" },
};
const switcher_items = [_]ui.MenuItem{
    .{ .label = "THE DISPOSSESSED", .detail = "NOW - AUDIOBOOK - CHAPTER 7" },
    .{ .label = "METROID ZERO MISSION", .detail = "TODAY - GAME BOY ADVANCE" },
    .{ .label = "THE MEMORY PALACE", .detail = "YESTERDAY - PODCAST" },
    .{ .label = "CELESTE", .detail = "MONDAY - PORT" },
};
const quick_items = [_]ui.MenuItem{
    .{ .label = "RESUME GAME", .detail = "RETURN TO PLAY" }, .{ .label = "SAVE STATE", .detail = "SLOT 1" },
    .{ .label = "LOAD STATE", .detail = "SLOT 1" },          .{ .label = "CONTROLS", .detail = "DEFAULT PROFILE" },
    .{ .label = "DISPLAY", .detail = "INTEGER SCALE" },      .{ .label = "QUIT TO HOME", .detail = "SAVE AND CLOSE" },
};

pub const Model = struct {
    page: Page = .home,
    selected: usize = 0,
    return_page: Page = .games,
    favorite: bool = false,
    playing: bool = true,
    progress_percent: u8 = 40,
    revision: u64 = 1,

    pub fn preview(page: Page, selected: usize) Model {
        var result = Model{ .page = page, .selected = selected };
        if (result.selected >= result.itemCount()) result.selected = 0;
        return result;
    }

    pub fn apply(self: *Model, action: Action) bool {
        const before = self.*;
        switch (action) {
            .up => self.selected = if (self.selected == 0) self.itemCount() - 1 else self.selected - 1,
            .down => self.selected = (self.selected + 1) % self.itemCount(),
            .left => if (self.page == .now_playing) {
                self.progress_percent -|= 3;
            },
            .right => if (self.page == .now_playing) {
                self.progress_percent = @min(self.progress_percent + 3, 100);
            },
            .confirm => self.confirm(),
            .back => self.goBack(),
            .home => self.open(.home, 0),
            .switcher => self.open(.switcher, 0),
            .options => if (self.page == .recent or self.page == .favorites or self.page == .games or self.page == .ports) {
                self.return_page = self.page;
                self.open(.game_detail, 0);
            },
            .favorite => if (self.page == .recent or self.page == .favorites or self.page == .games or self.page == .game_detail) {
                self.favorite = !self.favorite;
            },
        }
        const changed = before.page != self.page or before.selected != self.selected or before.favorite != self.favorite or
            before.playing != self.playing or before.progress_percent != self.progress_percent;
        if (changed) self.revision += 1;
        return changed;
    }

    fn open(self: *Model, page: Page, selected: usize) void {
        self.page = page;
        self.selected = selected;
    }
    fn confirm(self: *Model) void {
        switch (self.page) {
            .home => switch (self.selected) {
                0 => self.open(.now_playing, 0),
                1 => self.open(.systems, 0),
                2 => self.open(.music, 0),
                3 => self.open(.podcasts, 0),
                4 => self.open(.audiobooks, 0),
                5 => self.open(.ports, 0),
                else => self.open(.settings, 0),
            },
            .systems => self.open(.games, 0),
            .music, .podcasts, .audiobooks => self.open(.now_playing, 0),
            .now_playing => self.playing = !self.playing,
            .recent, .favorites, .games, .ports => {
                self.return_page = self.page;
                self.open(.game_detail, 0);
            },
            .game_detail => self.open(.quick_menu, 0),
            .switcher => switch (self.selected) {
                0, 2 => self.open(.now_playing, 0),
                1 => self.open(.quick_menu, 0),
                else => self.open(.game_detail, 0),
            },
            .quick_menu => if (self.selected == quick_items.len - 1) self.open(.home, 0),
            .settings => {},
        }
    }
    fn goBack(self: *Model) void {
        switch (self.page) {
            .home => {},
            .games => self.open(.systems, 0),
            .game_detail => self.open(self.return_page, 0),
            .now_playing => self.open(.home, 0),
            .quick_menu => self.open(.game_detail, 0),
            else => self.open(.home, homeSelection(self.page)),
        }
    }
    fn homeSelection(page: Page) usize {
        return switch (page) {
            .recent, .favorites, .systems, .games => 1,
            .music => 2,
            .podcasts => 3,
            .audiobooks => 4,
            .ports => 5,
            .settings => 6,
            else => 0,
        };
    }
    fn itemCount(self: *const Model) usize {
        return switch (self.page) {
            .home => home_items.len,
            .recent => recent_items.len,
            .favorites => favorite_items.len,
            .systems => system_items.len,
            .games => game_items.len,
            .music => music_items.len,
            .podcasts => podcast_items.len,
            .audiobooks => audiobook_items.len,
            .now_playing => 1,
            .ports => port_items.len,
            .settings => setting_items.len,
            .game_detail => 1,
            .switcher => switcher_items.len,
            .quick_menu => quick_items.len,
        };
    }
    pub fn tree(self: *const Model) ui.Tree {
        return switch (self.page) {
            .home => ui.dashboard(&home_items, self.selected),
            .recent => ui.menu("RECENT", &recent_items, self.selected, "A PLAY   X OPTIONS   Y FAVORITE"),
            .favorites => ui.menu("FAVORITES", &favorite_items, self.selected, "A PLAY   X OPTIONS   Y REMOVE"),
            .systems => ui.menu("LIBRARY", &system_items, self.selected, "A OPEN   L R SYSTEM   SELECT SWITCHER"),
            .games => ui.menu("GAME BOY ADVANCE", &game_items, self.selected, "A PLAY   X OPTIONS   Y FAVORITE"),
            .music => ui.menu("MUSIC", &music_items, self.selected, "A OPEN   SELECT NOW PLAYING"),
            .podcasts => ui.menu("PODCASTS", &podcast_items, self.selected, "A OPEN   X DOWNLOAD OPTIONS"),
            .audiobooks => ui.menu("AUDIOBOOKS", &audiobook_items, self.selected, "A OPEN   X BOOK OPTIONS"),
            .now_playing => ui.nowPlaying(self.playing, self.progress_percent),
            .ports => ui.menu("PORTS", &port_items, self.selected, "A OPEN   X DETAILS"),
            .settings => ui.menu("SETTINGS", &setting_items, self.selected, "A OPEN   B BACK"),
            .game_detail => ui.gameDetail(self.favorite),
            .switcher => ui.menu("ACTIVITY SWITCHER", &switcher_items, self.selected, "A RESUME   B HOME   SELECT CLOSE"),
            .quick_menu => ui.menu("QUICK MENU", &quick_items, self.selected, "A SELECT   B RESUME"),
        };
    }
};

test "resume-first flow reaches library, game details and home" {
    const testing = @import("std").testing;
    var state = Model{};
    state.selected = 1;
    try testing.expect(state.apply(.confirm));
    try testing.expectEqual(Page.systems, state.page);
    try testing.expect(state.apply(.confirm));
    try testing.expectEqual(Page.games, state.page);
    try testing.expect(state.apply(.options));
    try testing.expectEqual(Page.game_detail, state.page);
    try testing.expect(state.apply(.favorite));
    try testing.expect(state.favorite);
    try testing.expect(state.apply(.home));
    try testing.expectEqual(Page.home, state.page);
}
test "navigation wraps and switcher is globally available" {
    const testing = @import("std").testing;
    var state = Model{};
    try testing.expect(state.apply(.up));
    try testing.expectEqual(@as(usize, home_items.len - 1), state.selected);
    try testing.expect(state.apply(.switcher));
    try testing.expectEqual(Page.switcher, state.page);
    try testing.expect(state.apply(.confirm));
    try testing.expectEqual(Page.now_playing, state.page);
}
test "now playing responds without changing the navigation hierarchy" {
    const testing = @import("std").testing;
    var state = Model.preview(.now_playing, 0);
    try testing.expect(state.apply(.confirm));
    try testing.expect(!state.playing);
    try testing.expect(state.apply(.right));
    try testing.expectEqual(@as(u8, 43), state.progress_percent);
    try testing.expect(state.apply(.left));
    try testing.expectEqual(@as(u8, 40), state.progress_percent);
}
