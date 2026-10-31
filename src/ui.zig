// SPDX-License-Identifier: GPL-2.0-only
pub const Color = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    a: u8 = 0xff,
};

pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

pub const Text = struct {
    bounds: Rect,
    value: []const u8,
    color: Color,
    scale: u8 = 3,
};

pub const Bar = struct {
    bounds: Rect,
    color: Color,
};

pub const MenuRow = struct {
    bounds: Rect,
    label: []const u8,
    selected: bool,
    disclosure: bool = true,
};

pub const Battery = struct {
    bounds: Rect,
    percent: u8,
};

pub const Element = union(enum) {
    bar: Bar,
    text: Text,
    menu_row: MenuRow,
    battery: Battery,
};

pub const Tree = struct {
    background: Color,
    elements: [24]Element = undefined,
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
};

pub const Menu = struct {
    title: []const u8,
    items: []const []const u8,
    selected: usize,
    battery_percent: u8 = 82,

    pub fn tree(self: Menu) Tree {
        var result = Tree{ .background = palette.paper };
        result.add(.{ .bar = .{ .bounds = .{ .x = 0, .y = 0, .width = 1024, .height = 54 }, .color = palette.chrome } });
        result.add(.{ .text = .{ .bounds = .{ .x = 28, .y = 17, .width = 220, .height = 28 }, .value = "BRICK", .color = palette.ink, .scale = 2 } });
        result.add(.{ .battery = .{ .bounds = .{ .x = 914, .y = 15, .width = 76, .height = 26 }, .percent = self.battery_percent } });
        result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 86, .width = 900, .height = 55 }, .value = self.title, .color = palette.ink, .scale = 5 } });

        const first_y: u16 = 164;
        const row_height: u16 = 82;
        for (self.items, 0..) |label, index| {
            const y: u16 = first_y + @as(u16, @intCast(index)) * row_height;
            result.add(.{ .menu_row = .{
                .bounds = .{ .x = 28, .y = y, .width = 968, .height = 72 },
                .label = label,
                .selected = index == self.selected,
            } });
        }
        result.add(.{ .text = .{ .bounds = .{ .x = 42, .y = 724, .width = 940, .height = 28 }, .value = "A SELECT     B BACK", .color = palette.quiet, .scale = 2 } });
        return result;
    }
};

pub fn splash() Tree {
    var result = Tree{ .background = palette.paper };
    result.add(.{ .bar = .{ .bounds = .{ .x = 332, .y = 232, .width = 360, .height = 214 }, .color = palette.white } });
    result.add(.{ .text = .{ .bounds = .{ .x = 395, .y = 284, .width = 300, .height = 64 }, .value = "BRICK", .color = palette.ink, .scale = 7 } });
    result.add(.{ .bar = .{ .bounds = .{ .x = 420, .y = 376, .width = 184, .height = 8 }, .color = palette.blue } });
    result.add(.{ .text = .{ .bounds = .{ .x = 438, .y = 404, .width = 220, .height = 30 }, .value = "STARTING", .color = palette.quiet, .scale = 2 } });
    return result;
}
