// SPDX-License-Identifier: GPL-2.0-only
const ui = @import("ui.zig");

pub const width = 1024;
pub const height = 768;

pub const Surface = struct {
    pixels: []u32,

    pub fn render(self: Surface, tree: *const ui.Tree) void {
        @memset(self.pixels, pack(tree.background));
        for (tree.slice()) |element| switch (element) {
            .bar => |bar| self.fill(bar.bounds, bar.color),
            .text => |text| self.drawText(text.bounds.x, text.bounds.y, text.value, text.color, text.scale),
            .menu_row => |row| self.menuRow(row),
            .battery => |battery| self.drawBattery(battery),
        };
    }

    fn pack(color: ui.Color) u32 {
        return @bitCast(color);
    }

    fn fill(self: Surface, rect: ui.Rect, color: ui.Color) void {
        const right = @min(@as(usize, rect.x) + rect.width, width);
        const bottom = @min(@as(usize, rect.y) + rect.height, height);
        var y: usize = rect.y;
        while (y < bottom) : (y += 1) {
            @memset(self.pixels[y * width + rect.x .. y * width + right], pack(color));
        }
    }

    fn menuRow(self: Surface, row: ui.MenuRow) void {
        if (row.selected) {
            self.fill(row.bounds, ui.palette.blue);
            self.fill(.{ .x = row.bounds.x, .y = row.bounds.y, .width = 8, .height = row.bounds.height }, ui.palette.blue_dark);
        } else {
            self.fill(row.bounds, ui.palette.white);
            self.fill(.{ .x = row.bounds.x, .y = row.bounds.y + row.bounds.height - 1, .width = row.bounds.width, .height = 1 }, ui.palette.chrome);
        }
        const color = if (row.selected) ui.palette.white else ui.palette.ink;
        self.drawText(row.bounds.x + 26, row.bounds.y + 21, row.label, color, 4);
        if (row.disclosure) self.drawChevron(row.bounds.x + row.bounds.width - 38, row.bounds.y + 25, color);
    }

    fn drawBattery(self: Surface, battery: ui.Battery) void {
        const body = battery.bounds;
        self.fill(.{ .x = body.x, .y = body.y, .width = body.width - 8, .height = 3 }, ui.palette.ink);
        self.fill(.{ .x = body.x, .y = body.y + body.height - 3, .width = body.width - 8, .height = 3 }, ui.palette.ink);
        self.fill(.{ .x = body.x, .y = body.y, .width = 3, .height = body.height }, ui.palette.ink);
        self.fill(.{ .x = body.x + body.width - 11, .y = body.y, .width = 3, .height = body.height }, ui.palette.ink);
        self.fill(.{ .x = body.x + body.width - 8, .y = body.y + 7, .width = 8, .height = body.height - 14 }, ui.palette.ink);
        const capacity: u16 = body.width - 17;
        const charge: u16 = @intCast((@as(u32, capacity) * battery.percent) / 100);
        self.fill(.{ .x = body.x + 6, .y = body.y + 6, .width = charge, .height = body.height - 12 }, ui.palette.blue);
    }

    fn drawChevron(self: Surface, x: u16, y: u16, color: ui.Color) void {
        var step: u16 = 0;
        while (step < 11) : (step += 1) {
            self.fill(.{ .x = x + step, .y = y + step, .width = 4, .height = 4 }, color);
            self.fill(.{ .x = x + 10 - step, .y = y + 10 + step, .width = 4, .height = 4 }, color);
        }
    }

    fn drawText(self: Surface, x: u16, y: u16, value: []const u8, color: ui.Color, scale: u8) void {
        var cursor: u16 = x;
        for (value) |character| {
            const rows = glyph(character);
            for (rows, 0..) |bits, row| {
                var column: u3 = 0;
                while (column < 5) : (column += 1) {
                    if ((bits & (@as(u5, 1) << @intCast(4 - column))) != 0) {
                        self.fill(.{
                            .x = cursor + @as(u16, column) * scale,
                            .y = y + @as(u16, @intCast(row)) * scale,
                            .width = scale,
                            .height = scale,
                        }, color);
                    }
                }
            }
            cursor += 6 * @as(u16, scale);
        }
    }
};

fn glyph(character: u8) [7]u5 {
    return switch (character) {
        'A' => .{ 0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
        'B' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110 },
        'C' => .{ 0b01111, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b01111 },
        'D' => .{ 0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110 },
        'E' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111 },
        'F' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000 },
        'G' => .{ 0b01111, 0b10000, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111 },
        'H' => .{ 0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
        'I' => .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111 },
        'K' => .{ 0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001 },
        'L' => .{ 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111 },
        'M' => .{ 0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001 },
        'N' => .{ 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001 },
        'O' => .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        'P' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000 },
        'R' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001 },
        'S' => .{ 0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110 },
        'T' => .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 },
        'U' => .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        'V' => .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100 },
        'W' => .{ 0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010 },
        'Y' => .{ 0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100 },
        '-' => .{ 0, 0, 0, 0b11111, 0, 0, 0 },
        ' ' => .{ 0, 0, 0, 0, 0, 0, 0 },
        else => .{ 0b11111, 0b00001, 0b00010, 0b00100, 0b00100, 0, 0b00100 },
    };
}
