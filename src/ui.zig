// SPDX-License-Identifier: GPL-2.0-only
pub const Color = packed struct(u32) { b: u8, g: u8, r: u8, a: u8 = 0xff };
pub const Rect = struct { x: u16, y: u16, width: u16, height: u16 };
pub const Text = struct { bounds: Rect, value: []const u8, color: Color, scale: u8 = 3 };
pub const Bar = struct { bounds: Rect, color: Color };
pub const MenuItem = struct { label: []const u8, detail: []const u8 = "", disclosure: bool = true };
pub const MenuRow = struct {
    bounds: Rect,
    label: []const u8,
    detail: []const u8 = "",
    selected: bool,
    disclosure: bool = true,
    label_scale: u8 = 3,
    detail_scale: u8 = 2,
};
pub const Battery = struct { bounds: Rect, percent: u8 };
pub const Element = union(enum) { bar: Bar, text: Text, menu_row: MenuRow, battery: Battery };
pub const Tree = struct {
    background: Color,
    elements: [48]Element = undefined,
    len: usize = 0,
    pub fn add(self: *Tree, element: Element) void {
        self.elements[self.len] = element;
        self.len += 1;
    }
    pub fn slice(self: *const Tree) []const Element {
        return self.elements[0..self.len];
    }
};

pub const palette = struct {
    pub const white = Color{ .r = 0xff, .g = 0xff, .b = 0xff };
    pub const paper = Color{ .r = 0xf4, .g = 0xf4, .b = 0xf2 };
    pub const chrome = Color{ .r = 0xda, .g = 0xdc, .b = 0xdd };
    pub const ink = Color{ .r = 0x17, .g = 0x19, .b = 0x1c };
    pub const quiet = Color{ .r = 0x63, .g = 0x67, .b = 0x6c };
    pub const blue = Color{ .r = 0x1f, .g = 0x72, .b = 0xcf };
    pub const blue_dark = Color{ .r = 0x0e, .g = 0x4e, .b = 0x9b };
    pub const navy = Color{ .r = 0x12, .g = 0x26, .b = 0x3f };
    pub const gold = Color{ .r = 0xed, .g = 0xb8, .b = 0x31 };
};

fn chrome(result: *Tree, title: []const u8) void {
    result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 0, .width = 1024, .height = 54 }, .color = palette.chrome } });
    result.add(.{ .text = .{ .bounds = .{ .x = 28, .y = 17, .width = 220, .height = 28 }, .value = "BRICK", .color = palette.ink, .scale = 2 } });
    result.add(.{ .battery = .{ .bounds = .{ .x = 914, .y = 15, .width = 76, .height = 26 }, .percent = 82 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 74, .width = 900, .height = 48 }, .value = title, .color = palette.ink, .scale = 5 } });
}

pub fn menu(title: []const u8, items: []const MenuItem, selected: usize, footer: []const u8) Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, title);
    const visible_count = 6;
    const first = if (items.len <= visible_count or selected < visible_count) 0 else selected + 1 - visible_count;
    const last = @min(first + visible_count, items.len);
    const row_height: u16 = 94;
    for (items[first..last], 0..) |item, visible_index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = 28, .y = 136 + @as(u16, @intCast(visible_index)) * row_height, .width = 968, .height = 86 },
        .label = item.label,
        .detail = item.detail,
        .selected = first + visible_index == selected,
        .disclosure = item.disclosure,
        .label_scale = 4,
        .detail_scale = 3,
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 730, .width = 940, .height = 28 }, .value = footer, .color = palette.quiet, .scale = 3 } });
    return result;
}

pub fn dashboard(items: []const MenuItem, selected: usize) Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, "HOME");
    result.add(.{ .bar = .{ .bounds = .{ .x = 28, .y = 130, .width = 968, .height = 136 }, .color = if (selected == 0) palette.blue else palette.navy } });
    result.add(.{ .text = .{ .bounds = .{ .x = 56, .y = 150, .width = 300, .height = 24 }, .value = "CONTINUE LISTENING", .color = palette.white, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 56, .y = 186, .width = 780, .height = 42 }, .value = "THE DISPOSSESSED", .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 56, .y = 238, .width = 560, .height = 20 }, .value = "CHAPTER 7 - 4H 18M LEFT", .color = palette.chrome, .scale = 2 } });
    const row_height: u16 = 62;
    for (items[1..], 1..) |item, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = 28, .y = 278 + @as(u16, @intCast(index - 1)) * row_height, .width = 968, .height = 58 },
        .label = item.label,
        .detail = item.detail,
        .selected = index == selected,
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 738, .width = 940, .height = 20 }, .value = "A SELECT   MENU HOME   F1 SESSIONS", .color = palette.quiet, .scale = 2 } });
    return result;
}

pub fn nowPlaying(playing: bool, progress_percent: u8) Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, "NOW PLAYING");
    result.add(.{ .bar = .{ .bounds = .{ .x = 62, .y = 144, .width = 308, .height = 308 }, .color = palette.navy } });
    result.add(.{ .text = .{ .bounds = .{ .x = 104, .y = 254, .width = 230, .height = 40 }, .value = "THE", .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 104, .y = 302, .width = 230, .height = 40 }, .value = "DISPOSSESSED", .color = palette.white, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 420, .y = 168, .width = 540, .height = 40 }, .value = "THE DISPOSSESSED", .color = palette.ink, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 420, .y = 224, .width = 540, .height = 24 }, .value = "URSULA K LE GUIN", .color = palette.quiet, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 420, .y = 286, .width = 540, .height = 24 }, .value = "CHAPTER 7", .color = palette.ink, .scale = 3 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 420, .y = 354, .width = 514, .height = 8 }, .color = palette.chrome } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 420, .y = 354, .width = @intCast((@as(u32, 514) * progress_percent) / 100), .height = 8 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 420, .y = 382, .width = 220, .height = 20 }, .value = "5H 12M", .color = palette.quiet, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 810, .y = 382, .width = 180, .height = 20 }, .value = "9H 30M", .color = palette.quiet, .scale = 2 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 420, .y = 438, .width = 148, .height = 72 }, .color = palette.white } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 584, .y = 438, .width = 186, .height = 72 }, .color = palette.blue } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 786, .y = 438, .width = 148, .height = 72 }, .color = palette.white } });
    result.add(.{ .text = .{ .bounds = .{ .x = 454, .y = 464, .width = 100, .height = 28 }, .value = "-30", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = if (playing) 642 else 660, .y = 460, .width = 90, .height = 28 }, .value = if (playing) "PAUSE" else "PLAY", .color = palette.white, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 824, .y = 464, .width = 100, .height = 28 }, .value = "+30", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 420, .y = 546, .width = 440, .height = 22 }, .value = "SPEED 1.2X   SLEEP OFF", .color = palette.ink, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 738, .width = 940, .height = 20 }, .value = "A PAUSE   LEFT RIGHT SEEK   X CHAPTERS", .color = palette.quiet, .scale = 2 } });
    return result;
}

pub fn gameLibrary(items: []const MenuItem, selected: usize) Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, "GAME BOY ADVANCE");
    result.add(.{ .text = .{ .bounds = .{ .x = 818, .y = 88, .width = 170, .height = 28 }, .value = "42 GAMES", .color = palette.quiet, .scale = 3 } });
    const row_height: u16 = 90;
    for (items, 0..) |item, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = 28, .y = 136 + @as(u16, @intCast(index)) * row_height, .width = 606, .height = 84 },
        .label = item.label,
        .detail = item.detail,
        .selected = index == selected,
        .disclosure = false,
        .label_scale = 4,
        .detail_scale = 3,
    } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 658, .y = 136, .width = 338, .height = 448 }, .color = palette.white } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 686, .y = 160, .width = 282, .height = 282 }, .color = palette.navy } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 710, .y = 184, .width = 234, .height = 234 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 738, .y = 268, .width = 190, .height = 32 }, .value = "METROID", .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 758, .y = 316, .width = 150, .height = 32 }, .value = "ZERO", .color = palette.white, .scale = 5 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 676, .y = 470, .width = 300, .height = 28 }, .value = "METROID ZERO", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 676, .y = 508, .width = 300, .height = 28 }, .value = "RESUME - 24 MIN", .color = palette.blue_dark, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 676, .y = 546, .width = 300, .height = 28 }, .value = "PLAYED 3H 24M", .color = palette.quiet, .scale = 3 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 28, .y = 640, .width = 968, .height = 62 }, .color = palette.white } });
    result.add(.{ .text = .{ .bounds = .{ .x = 52, .y = 656, .width = 900, .height = 28 }, .value = "L R SYSTEM   X FILTER", .color = palette.quiet, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 730, .width = 940, .height = 28 }, .value = "A OPEN   B SYSTEMS   F1 SESSIONS", .color = palette.quiet, .scale = 3 } });
    return result;
}

pub fn gameDetail(favorite: bool, selected: usize) Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, "GAME");
    result.add(.{ .bar = .{ .bounds = .{ .x = 44, .y = 142, .width = 316, .height = 420 }, .color = palette.navy } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 68, .y = 168, .width = 268, .height = 368 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 100, .y = 308, .width = 210, .height = 80 }, .value = "METROID", .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 100, .y = 352, .width = 210, .height = 80 }, .value = "ZERO", .color = palette.white, .scale = 5 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 402, .y = 156, .width = 560, .height = 42 }, .value = "METROID ZERO", .color = palette.ink, .scale = 5 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 402, .y = 214, .width = 540, .height = 28 }, .value = "GAME BOY ADVANCE", .color = palette.quiet, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 402, .y = 266, .width = 540, .height = 28 }, .value = "LAST PLAYED TODAY", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 402, .y = 304, .width = 540, .height = 28 }, .value = "PLAY TIME 3H 24M", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 402, .y = 342, .width = 540, .height = 28 }, .value = if (favorite) "FAVORITE YES" else "FAVORITE NO", .color = palette.ink, .scale = 3 } });
    const actions = [_]MenuItem{
        .{ .label = "RESUME", .detail = "AUTO CHECKPOINT - 24 MIN" },
        .{ .label = "START NEW", .detail = "KEEP EXISTING SAVES" },
        .{ .label = "CHECKPOINTS", .detail = "AUTO + 4 MANUAL" },
        .{ .label = "GAME SETTINGS", .detail = "RECOMMENDED PROFILE" },
    };
    for (actions, 0..) |action, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = 402, .y = 394 + @as(u16, @intCast(index)) * 76, .width = 560, .height = 70 },
        .label = action.label,
        .detail = action.detail,
        .selected = index == selected,
        .disclosure = index >= 2,
        .label_scale = 4,
        .detail_scale = 3,
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 730, .width = 940, .height = 28 }, .value = "A SELECT   Y FAVORITE   B LIBRARY", .color = palette.quiet, .scale = 3 } });
    return result;
}

pub fn gameMenu(items: []const MenuItem, selected: usize) Tree {
    var result = Tree{ .background = palette.navy };
    result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 0, .width = 316, .height = 768 }, .color = palette.navy } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 500, .width = 316, .height = 268 }, .color = palette.blue_dark } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 64, .y = 154, .width = 188, .height = 188 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 96, .y = 222, .width = 150, .height = 32 }, .value = "METROID", .color = palette.white, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 106, .y = 266, .width = 120, .height = 32 }, .value = "ZERO", .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 542, .width = 230, .height = 28 }, .value = "METROID ZERO", .color = palette.white, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 582, .width = 230, .height = 28 }, .value = "PAUSED - GBA", .color = palette.chrome, .scale = 3 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 316, .y = 0, .width = 708, .height = 768 }, .color = palette.paper } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 316, .y = 0, .width = 708, .height = 54 }, .color = palette.chrome } });
    result.add(.{ .text = .{ .bounds = .{ .x = 344, .y = 15, .width = 250, .height = 28 }, .value = "GAME MENU", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 350, .y = 78, .width = 620, .height = 42 }, .value = "GAME", .color = palette.ink, .scale = 4 } });
    const row_height: u16 = 84;
    for (items, 0..) |item, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = 342, .y = 128 + @as(u16, @intCast(index)) * row_height, .width = 656, .height = 78 },
        .label = item.label,
        .detail = item.detail,
        .selected = index == selected,
        .disclosure = item.disclosure,
        .label_scale = 4,
        .detail_scale = 3,
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 350, .y = 730, .width = 630, .height = 28 }, .value = "A SELECT   B RESUME", .color = palette.quiet, .scale = 3 } });
    return result;
}

pub fn checkpoints(items: []const MenuItem, selected: usize) Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, "CHECKPOINTS");
    result.add(.{ .text = .{ .bounds = .{ .x = 700, .y = 88, .width = 288, .height = 28 }, .value = "AUTO + 4 MANUAL", .color = palette.quiet, .scale = 3 } });
    const row_height: u16 = 96;
    for (items, 0..) |item, index| {
        result.add(.{ .bar = .{ .bounds = .{ .x = 28, .y = 140 + @as(u16, @intCast(index)) * row_height, .width = 132, .height = 84 }, .color = if (index == 0) palette.blue else palette.navy } });
        result.add(.{ .menu_row = .{
            .bounds = .{ .x = 172, .y = 140 + @as(u16, @intCast(index)) * row_height, .width = 824, .height = 84 },
            .label = item.label,
            .detail = item.detail,
            .selected = index == selected,
            .disclosure = false,
            .label_scale = 4,
            .detail_scale = 3,
        } });
    }
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 730, .width = 940, .height = 28 }, .value = "A LOAD   X SAVE NEW   B BACK", .color = palette.quiet, .scale = 3 } });
    return result;
}

pub fn storageStatus() Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, "GAME STORAGE");
    result.add(.{ .bar = .{ .bounds = .{ .x = 42, .y = 142, .width = 940, .height = 118 }, .color = palette.white } });
    result.add(.{ .text = .{ .bounds = .{ .x = 70, .y = 166, .width = 600, .height = 28 }, .value = "SD CARD READY", .color = palette.ink, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 218, .width = 740, .height = 28 }, .value = "BRICK LIBRARY - 57 GB FREE", .color = palette.quiet, .scale = 3 } });
    const rows = [_]MenuItem{
        .{ .label = "ROMS", .detail = "/ROMS/GBA - 42 GAMES", .disclosure = false },
        .{ .label = "BIOS", .detail = "/BIOS - ALL REQUIRED FILES FOUND", .disclosure = false },
        .{ .label = "ARTWORK", .detail = "IMPORTED WHEN AVAILABLE", .disclosure = false },
        .{ .label = "RESCAN", .detail = "LAST SCAN 18 SECONDS AGO" },
    };
    for (rows, 0..) |row, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = 42, .y = 286 + @as(u16, @intCast(index)) * 84, .width = 940, .height = 76 },
        .label = row.label,
        .detail = row.detail,
        .selected = index == 3,
        .disclosure = row.disclosure,
        .label_scale = 4,
        .detail_scale = 3,
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 730, .width = 940, .height = 28 }, .value = "A RESCAN   X HELP   B BACK", .color = palette.quiet, .scale = 3 } });
    return result;
}

pub fn emptyLibrary() Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, "GAMES");
    result.add(.{ .bar = .{ .bounds = .{ .x = 142, .y = 150, .width = 740, .height = 410 }, .color = palette.white } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 428, .y = 194, .width = 168, .height = 112 }, .color = palette.navy } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 448, .y = 218, .width = 128, .height = 68 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 300, .y = 336, .width = 520, .height = 42 }, .value = "NO GAMES FOUND", .color = palette.ink, .scale = 5 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 262, .y = 402, .width = 600, .height = 28 }, .value = "COPY GAMES TO /ROMS/SYSTEM", .color = palette.quiet, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 326, .y = 442, .width = 520, .height = 28 }, .value = "EXAMPLE /ROMS/GBA", .color = palette.quiet, .scale = 3 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 328, .y = 494, .width = 368, .height = 70 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 416, .y = 518, .width = 240, .height = 28 }, .value = "SCAN AGAIN", .color = palette.white, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 730, .width = 940, .height = 28 }, .value = "A SCAN   X HELP   B HOME", .color = palette.quiet, .scale = 3 } });
    return result;
}

pub fn saveData(items: []const MenuItem, selected: usize) Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, "SAVE DATA");
    result.add(.{ .bar = .{ .bounds = .{ .x = 42, .y = 142, .width = 940, .height = 108 }, .color = palette.white } });
    result.add(.{ .text = .{ .bounds = .{ .x = 70, .y = 164, .width = 430, .height = 32 }, .value = "UP TO DATE", .color = palette.blue_dark, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 212, .width = 620, .height = 28 }, .value = "SYNCED 18 SEC AGO - 2 DEVICES", .color = palette.quiet, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 720, .y = 166, .width = 230, .height = 28 }, .value = "BACKUP TODAY", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 756, .y = 212, .width = 190, .height = 28 }, .value = "14 VERSIONS", .color = palette.quiet, .scale = 3 } });
    const row_height: u16 = 88;
    for (items, 0..) |item, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = 42, .y = 276 + @as(u16, @intCast(index)) * row_height, .width = 940, .height = 80 },
        .label = item.label,
        .detail = item.detail,
        .selected = index == selected,
        .disclosure = item.disclosure,
        .label_scale = 4,
        .detail_scale = 3,
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 730, .width = 940, .height = 28 }, .value = "A SELECT   B SETTINGS", .color = palette.quiet, .scale = 3 } });
    return result;
}

pub fn saveConflict(selected: usize) Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, "CHOOSE PROGRESS");
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 132, .width = 720, .height = 32 }, .value = "METROID ZERO MISSION", .color = palette.ink, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 176, .width = 850, .height = 28 }, .value = "PLAYED ON BOTH DEVICES", .color = palette.quiet, .scale = 3 } });

    const left_color = if (selected == 0) palette.blue else palette.white;
    const right_color = if (selected == 1) palette.blue else palette.white;
    const left_text = if (selected == 0) palette.white else palette.ink;
    const right_text = if (selected == 1) palette.white else palette.ink;
    const left_quiet = if (selected == 0) palette.chrome else palette.quiet;
    const right_quiet = if (selected == 1) palette.chrome else palette.quiet;

    result.add(.{ .bar = .{ .bounds = .{ .x = 42, .y = 226, .width = 450, .height = 286 }, .color = left_color } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 254, .width = 360, .height = 32 }, .value = "THIS BRICK", .color = left_text, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 312, .width = 350, .height = 32 }, .value = "TODAY 14:32", .color = left_text, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 370, .width = 350, .height = 28 }, .value = "3H 24M PLAYED", .color = left_quiet, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 414, .width = 350, .height = 28 }, .value = "NORFAIR", .color = left_quiet, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 462, .width = 350, .height = 28 }, .value = "MGBA - SAVE + STATE", .color = left_quiet, .scale = 3 } });

    result.add(.{ .bar = .{ .bounds = .{ .x = 532, .y = 226, .width = 450, .height = 286 }, .color = right_color } });
    result.add(.{ .text = .{ .bounds = .{ .x = 562, .y = 254, .width = 360, .height = 32 }, .value = "STEAM DECK", .color = right_text, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 562, .y = 312, .width = 350, .height = 32 }, .value = "TODAY 15:10", .color = right_text, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 562, .y = 370, .width = 350, .height = 28 }, .value = "3H 02M PLAYED", .color = right_quiet, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 562, .y = 414, .width = 350, .height = 28 }, .value = "KRAID", .color = right_quiet, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 562, .y = 462, .width = 350, .height = 28 }, .value = "MGBA - SAVE + STATE", .color = right_quiet, .scale = 3 } });

    result.add(.{ .bar = .{ .bounds = .{ .x = 42, .y = 546, .width = 940, .height = 102 }, .color = palette.white } });
    result.add(.{ .text = .{ .bounds = .{ .x = 70, .y = 568, .width = 700, .height = 32 }, .value = "BOTH VERSIONS ARE SAFE", .color = palette.ink, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 72, .y = 612, .width = 820, .height = 28 }, .value = "THE OTHER STAYS IN HISTORY", .color = palette.quiet, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 730, .width = 940, .height = 28 }, .value = "A KEEP   LEFT RIGHT CHOOSE   B LATER", .color = palette.quiet, .scale = 3 } });
    return result;
}

pub fn classic() Tree {
    const items = [_]MenuItem{ .{ .label = "GAMES" }, .{ .label = "PORTS" }, .{ .label = "FAVORITES" }, .{ .label = "SETTINGS" } };
    return menu("MENU", &items, 0, "A SELECT   B BACK");
}

pub fn richLibrary() Tree {
    var result = Tree{ .background = palette.navy };
    result.add(.{ .text = .{ .bounds = .{ .x = 38, .y = 30, .width = 700, .height = 44 }, .value = "GAME BOY ADVANCE", .color = palette.white, .scale = 4 } });
    result.add(.{ .battery = .{ .bounds = .{ .x = 914, .y = 28, .width = 76, .height = 26 }, .percent = 82 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 38, .y = 104, .width = 338, .height = 486 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 82, .y = 282, .width = 280, .height = 40 }, .value = "METROID", .color = palette.white, .scale = 5 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 82, .y = 340, .width = 280, .height = 40 }, .value = "ZERO", .color = palette.white, .scale = 6 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 424, .y = 132, .width = 550, .height = 40 }, .value = "METROID ZERO MISSION", .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 424, .y = 196, .width = 520, .height = 20 }, .value = "2004 - NINTENDO - ACTION", .color = palette.chrome, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 424, .y = 270, .width = 520, .height = 20 }, .value = "EXPLORE PLANET ZEBES AND", .color = palette.white, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 424, .y = 300, .width = 520, .height = 20 }, .value = "RECOVER THE STOLEN METROIDS", .color = palette.white, .scale = 2 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 424, .y = 398, .width = 520, .height = 76 }, .color = palette.gold } });
    result.add(.{ .text = .{ .bounds = .{ .x = 458, .y = 422, .width = 440, .height = 32 }, .value = "RESUME - 24 MIN", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 38, .y = 718, .width = 940, .height = 22 }, .value = "L R SYSTEM   A PLAY   X OPTIONS", .color = palette.chrome, .scale = 2 } });
    return result;
}

pub fn splash() Tree {
    var result = Tree{ .background = palette.paper };
    result.add(.{ .bar = .{ .bounds = .{ .x = 332, .y = 232, .width = 360, .height = 214 }, .color = palette.white } });
    result.add(.{ .text = .{ .bounds = .{ .x = 395, .y = 284, .width = 300, .height = 64 }, .value = "BRICK", .color = palette.ink, .scale = 7 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 420, .y = 376, .width = 184, .height = 8 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 438, .y = 404, .width = 220, .height = 30 }, .value = "STARTING", .color = palette.quiet, .scale = 2 } });
    return result;
}
