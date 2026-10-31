// SPDX-License-Identifier: GPL-2.0-only
pub const Color = packed struct(u32) { b: u8, g: u8, r: u8, a: u8 = 0xff };
pub const Rect = struct { x: u16, y: u16, width: u16, height: u16 };
pub const Text = struct { bounds: Rect, value: []const u8, color: Color, scale: u8 = 3 };
pub const Bar = struct { bounds: Rect, color: Color };
pub const MenuItem = struct { label: []const u8, detail: []const u8 = "", disclosure: bool = true };
pub const MenuRow = struct { bounds: Rect, label: []const u8, detail: []const u8 = "", selected: bool, disclosure: bool = true };
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
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 78, .width = 900, .height = 48 }, .value = title, .color = palette.ink, .scale = 4 } });
}

pub fn menu(title: []const u8, items: []const MenuItem, selected: usize, footer: []const u8) Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, title);
    const row_height: u16 = 86;
    for (items, 0..) |item, index| result.add(.{ .menu_row = .{
        .bounds = .{ .x = 28, .y = 144 + @as(u16, @intCast(index)) * row_height, .width = 968, .height = 78 },
        .label = item.label,
        .detail = item.detail,
        .selected = index == selected,
        .disclosure = item.disclosure,
    } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 738, .width = 940, .height = 20 }, .value = footer, .color = palette.quiet, .scale = 2 } });
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
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 738, .width = 940, .height = 20 }, .value = "A SELECT   MENU HOME   SELECT SWITCHER", .color = palette.quiet, .scale = 2 } });
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

pub fn gameDetail(favorite: bool) Tree {
    var result = Tree{ .background = palette.paper };
    chrome(&result, "GAME");
    result.add(.{ .bar = .{ .bounds = .{ .x = 44, .y = 142, .width = 316, .height = 420 }, .color = palette.navy } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 68, .y = 168, .width = 268, .height = 368 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 100, .y = 308, .width = 210, .height = 80 }, .value = "METROID", .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 100, .y = 352, .width = 210, .height = 80 }, .value = "ZERO", .color = palette.white, .scale = 5 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 402, .y = 162, .width = 560, .height = 40 }, .value = "METROID ZERO MISSION", .color = palette.ink, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 402, .y = 218, .width = 540, .height = 22 }, .value = "GAME BOY ADVANCE - 2004", .color = palette.quiet, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 402, .y = 278, .width = 540, .height = 22 }, .value = "LAST PLAYED TODAY", .color = palette.ink, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 402, .y = 318, .width = 540, .height = 22 }, .value = "PLAY TIME 3H 24M", .color = palette.ink, .scale = 2 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 402, .y = 358, .width = 540, .height = 22 }, .value = if (favorite) "FAVORITE YES" else "FAVORITE NO", .color = palette.ink, .scale = 2 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 402, .y = 430, .width = 560, .height = 82 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 436, .y = 454, .width = 490, .height = 32 }, .value = "RESUME GAME", .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 738, .width = 940, .height = 20 }, .value = "A RESUME   Y FAVORITE   B BACK", .color = palette.quiet, .scale = 2 } });
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
