// SPDX-License-Identifier: GPL-2.0-only
const catalog = @import("catalog.zig");

pub const Color = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    a: u8 = 0xff,
};

pub const Rect = struct { x: u16, y: u16, width: u16, height: u16 };
pub const Text = struct { bounds: Rect, value: []const u8, color: Color, scale: u8 = 3 };
pub const Bar = struct { bounds: Rect, color: Color };
pub const MenuRow = struct {
    bounds: Rect,
    label: []const u8,
    detail: []const u8 = "",
    selected: bool,
    disclosure: bool = true,
};
pub const Battery = struct { bounds: Rect, percent: u8 };
pub const Cover = struct { bounds: Rect, kind: catalog.Cover };
pub const GameScene = struct { bounds: Rect };
pub const OverlayRow = struct {
    bounds: Rect,
    label: []const u8,
    detail: []const u8,
    value: []const u8 = "",
    selected: bool,
    disclosure: bool = true,
};
pub const Element = union(enum) {
    bar: Bar,
    text: Text,
    menu_row: MenuRow,
    battery: Battery,
    cover: Cover,
    game_scene: GameScene,
    overlay_row: OverlayRow,
};

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
    pub const paper = Color{ .r = 0xf4, .g = 0xf2, .b = 0xed };
    pub const chrome = Color{ .r = 0xd9, .g = 0xdc, .b = 0xde };
    pub const chrome_dark = Color{ .r = 0xa4, .g = 0xaa, .b = 0xaf };
    pub const ink = Color{ .r = 0x16, .g = 0x19, .b = 0x1d };
    pub const quiet = Color{ .r = 0x67, .g = 0x6c, .b = 0x72 };
    pub const blue = Color{ .r = 0x1c, .g = 0x72, .b = 0xc9 };
    pub const blue_dark = Color{ .r = 0x0a, .g = 0x49, .b = 0x91 };
    pub const navy = Color{ .r = 0x13, .g = 0x25, .b = 0x3c };
    pub const sky = Color{ .r = 0x73, .g = 0xc8, .b = 0xea };
    pub const coral = Color{ .r = 0xe7, .g = 0x5c, .b = 0x4c };
    pub const gold = Color{ .r = 0xf2, .g = 0xb9, .b = 0x3b };
    pub const green = Color{ .r = 0x4e, .g = 0xa6, .b = 0x68 };
};

fn gameUnderlay(result: *Tree) void {
    result.add(.{ .game_scene = .{ .bounds = .{ .x = 0, .y = 0, .width = 1024, .height = 768 } } });
}

fn gameCaption(result: *Tree) void {
    result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 600, .width = 430, .height = 114 }, .color = palette.paper } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 600, .width = 430, .height = 2 }, .color = palette.chrome_dark } });
    result.add(.{ .text = .{ .bounds = .{ .x = 30, .y = 626, .width = 370, .height = 24 }, .value = "MINEKART MADNESS", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 30, .y = 674, .width = 350, .height = 18 }, .value = "NINTENDO NES  -  38 MIN", .color = palette.quiet, .scale = 2 } });
}

fn overlayFrame(result: *Tree, title: []const u8, section: []const u8) void {
    gameUnderlay(result);
    gameCaption(result);
    result.add(.{ .bar = .{ .bounds = .{ .x = 430, .y = 58, .width = 594, .height = 656 }, .color = palette.paper } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 428, .y = 58, .width = 2, .height = 656 }, .color = palette.chrome_dark } });
    header(result, title);
    result.add(.{ .text = .{ .bounds = .{ .x = 456, .y = 84, .width = 420, .height = 24 }, .value = section, .color = palette.quiet, .scale = 3 } });
}

pub fn overlayPause(selected: usize, state_slot: usize, saved: bool) Tree {
    const labels = [_][]const u8{ "CONTINUE", "SAVE STATE", "LOAD STATE", "GAME OPTIONS", "SAVE AND EXIT" };
    const slots = [_][]const u8{ "SLOT 3", "SLOT 2", "SLOT 1", "AUTO" };
    var result = Tree{ .background = palette.paper };
    overlayFrame(&result, "PAUSED", "GAME MENU");
    for (labels, 0..) |label, index| {
        const resolved_detail = if (index == 1)
            (if (saved) "SAVED JUST NOW" else "LEFT RIGHT CHANGES SLOT")
        else if (index == 2)
            "AUTO-BACKUP BEFORE LOAD"
        else if (index == 3)
            "CONTROLS  DISPLAY  PERFORMANCE"
        else if (index == 4)
            "AUTO-SAVES FIRST"
        else
            "BACK TO PLAY";
        result.add(.{ .overlay_row = .{
            .bounds = .{ .x = 446, .y = 126 + @as(u16, @intCast(index)) * 96, .width = 562, .height = 86 },
            .label = label,
            .detail = resolved_detail,
            .value = if (index == 1) slots[state_slot] else "",
            .selected = index == selected,
            .disclosure = index == 0 or index >= 2,
        } });
    }
    footer(&result, "UP DOWN MOVE     A SELECT     B OR MENU RESUME");
    return result;
}

pub fn overlayStates(selected: usize) Tree {
    const labels = [_][]const u8{ "SLOT 3", "SLOT 2", "SLOT 1", "AUTO BACKUP" };
    const details = [_][]const u8{ "NOW", "18 MIN AGO", "YESTERDAY", "BEFORE LAST LOAD" };
    var result = Tree{ .background = palette.paper };
    header(&result, "LOAD STATE");
    result.add(.{ .text = .{ .bounds = .{ .x = 30, .y = 86, .width = 520, .height = 32 }, .value = "CHOOSE A MOMENT", .color = palette.quiet, .scale = 3 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 46, .y = 196, .width = 576, .height = 426 }, .color = palette.chrome_dark } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 34, .y = 184, .width = 576, .height = 426 }, .color = palette.white } });
    result.add(.{ .game_scene = .{ .bounds = .{ .x = 46, .y = 196, .width = 552, .height = 414 } } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 46, .y = 540, .width = 552, .height = 70 }, .color = palette.white } });
    result.add(.{ .text = .{ .bounds = .{ .x = 70, .y = 565, .width = 420, .height = 22 }, .value = labels[selected], .color = palette.ink, .scale = 3 } });
    for (labels, details, 0..) |label, detail, index| {
        result.add(.{ .overlay_row = .{
            .bounds = .{ .x = 640, .y = 184 + @as(u16, @intCast(index)) * 104, .width = 354, .height = 94 },
            .label = label,
            .detail = detail,
            .selected = index == selected,
        } });
    }
    result.add(.{ .text = .{ .bounds = .{ .x = 36, .y = 670, .width = 900, .height = 18 }, .value = "A SAFETY BACKUP IS MADE BEFORE LOADING", .color = palette.blue, .scale = 2 } });
    footer(&result, "A LOAD          B BACK          MENU RESUME");
    return result;
}

pub fn overlayOptions(selected: usize, values: [4][]const u8) Tree {
    const labels = [_][]const u8{ "CONTROLS", "DISPLAY", "PERFORMANCE", "SHADER" };
    const details = [_][]const u8{ "PROFILE FOR THIS GAME", "SCALING MODE", "POWER PROFILE", "VIDEO FILTER" };
    var result = Tree{ .background = palette.paper };
    overlayFrame(&result, "GAME OPTIONS", "MINEKART MADNESS");
    for (labels, details, 0..) |label, detail, index| {
        result.add(.{ .overlay_row = .{
            .bounds = .{ .x = 446, .y = 126 + @as(u16, @intCast(index)) * 108, .width = 562, .height = 98 },
            .label = label,
            .detail = detail,
            .value = values[index],
            .selected = index == selected,
            .disclosure = false,
        } });
    }
    footer(&result, "LEFT RIGHT CHANGE     A NEXT     B BACK     MENU RESUME");
    return result;
}

fn header(result: *Tree, title: []const u8) void {
    result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 0, .width = 1024, .height = 58 }, .color = palette.chrome } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 56, .width = 1024, .height = 2 }, .color = palette.chrome_dark } });
    result.add(.{ .text = .{ .bounds = .{ .x = 28, .y = 18, .width = 260, .height = 24 }, .value = title, .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 810, .y = 20, .width = 80, .height = 20 }, .value = "12:42", .color = palette.quiet, .scale = 2 } });
    result.add(.{ .battery = .{ .bounds = .{ .x = 918, .y = 16, .width = 74, .height = 26 }, .percent = 82 } });
}

fn footer(result: *Tree, hint: []const u8) void {
    result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 714, .width = 1024, .height = 54 }, .color = palette.chrome } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 714, .width = 1024, .height = 2 }, .color = palette.chrome_dark } });
    result.add(.{ .text = .{ .bounds = .{ .x = 30, .y = 733, .width = 900, .height = 20 }, .value = hint, .color = palette.quiet, .scale = 2 } });
}

pub fn home(selected: usize) Tree {
    const items = [_][]const u8{ "GAMES", "RECENT", "FAVORITES", "SETTINGS" };
    var result = Tree{ .background = palette.paper };
    header(&result, "BRICK");
    result.add(.{ .text = .{ .bounds = .{ .x = 30, .y = 84, .width = 300, .height = 32 }, .value = "MENU", .color = palette.quiet, .scale = 3 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 510, .y = 58, .width = 2, .height = 656 }, .color = palette.chrome_dark } });
    for (items, 0..) |label, index| {
        result.add(.{ .menu_row = .{
            .bounds = .{ .x = 18, .y = 128 + @as(u16, @intCast(index)) * 92, .width = 476, .height = 82 },
            .label = label,
            .selected = index == selected,
        } });
    }
    result.add(.{ .cover = .{ .bounds = .{ .x = 604, .y = 130, .width = 320, .height = 320 }, .kind = .library } });
    result.add(.{ .text = .{ .bounds = .{ .x = 640, .y = 486, .width = 260, .height = 32 }, .value = "YOUR LIBRARY", .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 703, .y = 536, .width = 180, .height = 24 }, .value = "2 GAMES", .color = palette.quiet, .scale = 2 } });
    footer(&result, "A SELECT        B BACK        MENU HOME");
    return result;
}

pub fn library(selected: usize) Tree {
    var result = Tree{ .background = palette.paper };
    header(&result, "GAMES");
    result.add(.{ .text = .{ .bounds = .{ .x = 30, .y = 82, .width = 300, .height = 28 }, .value = "ALL GAMES", .color = palette.quiet, .scale = 3 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 520, .y = 58, .width = 2, .height = 656 }, .color = palette.chrome_dark } });
    for (catalog.games, 0..) |game, index| {
        result.add(.{ .menu_row = .{
            .bounds = .{ .x = 18, .y = 126 + @as(u16, @intCast(index)) * 108, .width = 486, .height = 98 },
            .label = game.title,
            .detail = game.system,
            .selected = index == selected,
        } });
    }
    const game = catalog.games[selected];
    result.add(.{ .cover = .{ .bounds = .{ .x = 612, .y = 112, .width = 322, .height = 322 }, .kind = game.cover } });
    result.add(.{ .text = .{ .bounds = .{ .x = 582, .y = 476, .width = 390, .height = 32 }, .value = game.title, .color = palette.ink, .scale = 3 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 650, .y = 526, .width = 300, .height = 24 }, .value = game.summary, .color = palette.quiet, .scale = 2 } });
    footer(&result, "A DETAILS       B BACK");
    return result;
}

pub fn gameDetail(index: usize, launch_failed: bool) Tree {
    const game = catalog.games[index];
    var result = Tree{ .background = palette.paper };
    header(&result, game.system);
    result.add(.{ .cover = .{ .bounds = .{ .x = 76, .y = 128, .width = 420, .height = 420 }, .kind = game.cover } });
    result.add(.{ .text = .{ .bounds = .{ .x = 548, .y = 148, .width = 430, .height = 42 }, .value = game.title, .color = palette.ink, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 550, .y = 226, .width = 380, .height = 24 }, .value = game.summary, .color = palette.quiet, .scale = 2 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 548, .y = 292, .width = 382, .height = 88 }, .color = palette.blue } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 548, .y = 292, .width = 8, .height = 88 }, .color = palette.blue_dark } });
    result.add(.{ .text = .{ .bounds = .{ .x = 666, .y = 323, .width = 200, .height = 28 }, .value = "PLAY", .color = palette.white, .scale = 4 } });
    result.add(.{ .text = .{ .bounds = .{ .x = 550, .y = 424, .width = 370, .height = 22 }, .value = "SAVES STAY ON THIS SD CARD", .color = palette.quiet, .scale = 2 } });
    if (launch_failed)
        result.add(.{ .text = .{ .bounds = .{ .x = 550, .y = 482, .width = 420, .height = 22 }, .value = "RETROARCH NOT INSTALLED", .color = palette.coral, .scale = 2 } });
    footer(&result, "A PLAY          B BACK");
    return result;
}

pub fn settings(selected: usize) Tree {
    const items = [_][]const u8{ "DISPLAY", "AUDIO", "NETWORK", "POWER", "ABOUT" };
    var result = Tree{ .background = palette.paper };
    header(&result, "SETTINGS");
    for (items, 0..) |label, index| {
        result.add(.{ .menu_row = .{
            .bounds = .{ .x = 28, .y = 94 + @as(u16, @intCast(index)) * 108, .width = 968, .height = 96 },
            .label = label,
            .selected = index == selected,
        } });
    }
    footer(&result, "A SELECT        B BACK");
    return result;
}

pub fn splash() Tree {
    var result = Tree{ .background = palette.paper };
    result.add(.{ .bar = .{ .bounds = .{ .x = 300, .y = 188, .width = 424, .height = 310 }, .color = palette.white } });
    result.add(.{ .cover = .{ .bounds = .{ .x = 422, .y = 226, .width = 180, .height = 180 }, .kind = .library } });
    result.add(.{ .text = .{ .bounds = .{ .x = 416, .y = 438, .width = 260, .height = 54 }, .value = "BRICK", .color = palette.ink, .scale = 6 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 424, .y = 518, .width = 176, .height = 7 }, .color = palette.blue } });
    return result;
}
