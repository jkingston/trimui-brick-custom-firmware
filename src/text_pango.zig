// SPDX-License-Identifier: GPL-2.0-only
// Runtime-loaded PangoFT2 backend: UTF-8, shaping, bidi and font fallback.
const design = @import("design.zig");
const std = @import("std");

const Object = opaque {};
const FontDescription = opaque {};
const pango_scale = 1024;
const pango_ellipsize_end = 3;
const ft_pixel_mode_gray = 2;

const Rectangle = extern struct { x: i32, y: i32, width: i32, height: i32 };

const Bitmap = extern struct {
    rows: u32,
    width: u32,
    pitch: i32,
    buffer: [*]u8,
    num_grays: u16,
    pixel_mode: u8,
    palette_mode: u8,
    palette: ?*anyopaque,
};

const Engine = struct {
    ft2: std.DynLib,
    pango: std.DynLib,
    gobject: std.DynLib,
    font_map: *Object,
    createContext: *const fn (*Object) callconv(.c) ?*Object,
    contextSetLanguage: *const fn (*Object, *Object) callconv(.c) void,
    languageFromString: *const fn ([*:0]const u8) callconv(.c) ?*Object,
    layoutSetAlignment: *const fn (*Object, i32) callconv(.c) void,
    layoutSetAttributes: *const fn (*Object, ?*Object) callconv(.c) void,
    attributeListNew: *const fn () callconv(.c) ?*Object,
    attributeListInsert: *const fn (*Object, *Object) callconv(.c) void,
    lineHeightNew: *const fn (i32) callconv(.c) ?*Object,
    layoutNew: *const fn (*Object) callconv(.c) ?*Object,
    layoutSetText: *const fn (*Object, [*]const u8, i32) callconv(.c) void,
    layoutSetHeight: *const fn (*Object, i32) callconv(.c) void,
    layoutSetWidth: *const fn (*Object, i32) callconv(.c) void,
    layoutSetEllipsize: *const fn (*Object, i32) callconv(.c) void,
    layoutSetSingleParagraph: *const fn (*Object, i32) callconv(.c) void,
    layoutSetAutoDirection: *const fn (*Object, i32) callconv(.c) void,
    layoutSetFont: *const fn (*Object, *FontDescription) callconv(.c) void,
    layoutGetPixelSize: *const fn (*Object, *i32, *i32) callconv(.c) void,
    layoutGetPixelExtents: *const fn (*Object, ?*Rectangle, ?*Rectangle) callconv(.c) void,
    layoutGetLineCount: *const fn (*Object) callconv(.c) i32,
    layoutIsEllipsized: *const fn (*Object) callconv(.c) i32,
    descriptionFromString: *const fn ([*:0]const u8) callconv(.c) ?*FontDescription,
    descriptionSetAbsoluteSize: *const fn (*FontDescription, f64) callconv(.c) void,
    renderLayout: *const fn (*Bitmap, *Object, i32, i32) callconv(.c) void,
    unref: *const fn (*Object) callconv(.c) void,

    fn symbol(library: *std.DynLib, comptime T: type, comptime name: [:0]const u8) !T {
        return library.lookup(T, name) orelse error.MissingPangoSymbol;
    }

    fn init() !Engine {
        var ft2 = std.DynLib.open("libpangoft2-1.0.so.0") catch
            std.DynLib.open("/lib64/libpangoft2-1.0.so.0") catch try std.DynLib.open("libpangoft2-1.0.so");
        errdefer ft2.close();
        var pango = std.DynLib.open("libpango-1.0.so.0") catch
            std.DynLib.open("/lib64/libpango-1.0.so.0") catch try std.DynLib.open("libpango-1.0.so");
        errdefer pango.close();
        var gobject = std.DynLib.open("libgobject-2.0.so.0") catch
            std.DynLib.open("/lib64/libgobject-2.0.so.0") catch try std.DynLib.open("libgobject-2.0.so");
        errdefer gobject.close();
        const NewMap = *const fn () callconv(.c) ?*Object;
        const newMap = try symbol(&ft2, NewMap, "pango_ft2_font_map_new");
        const font_map = newMap() orelse return error.PangoFontMap;
        return .{
            .ft2 = ft2,
            .pango = pango,
            .gobject = gobject,
            .font_map = font_map,
            .createContext = try symbol(&pango, @FieldType(Engine, "createContext"), "pango_font_map_create_context"),
            .contextSetLanguage = try symbol(&pango, @FieldType(Engine, "contextSetLanguage"), "pango_context_set_language"),
            .languageFromString = try symbol(&pango, @FieldType(Engine, "languageFromString"), "pango_language_from_string"),
            .layoutSetAlignment = try symbol(&pango, @FieldType(Engine, "layoutSetAlignment"), "pango_layout_set_alignment"),
            .layoutSetAttributes = try symbol(&pango, @FieldType(Engine, "layoutSetAttributes"), "pango_layout_set_attributes"),
            .attributeListNew = try symbol(&pango, @FieldType(Engine, "attributeListNew"), "pango_attr_list_new"),
            .attributeListInsert = try symbol(&pango, @FieldType(Engine, "attributeListInsert"), "pango_attr_list_insert"),
            .lineHeightNew = try symbol(&pango, @FieldType(Engine, "lineHeightNew"), "pango_attr_line_height_new_absolute"),
            .layoutNew = try symbol(&pango, @FieldType(Engine, "layoutNew"), "pango_layout_new"),
            .layoutSetText = try symbol(&pango, @FieldType(Engine, "layoutSetText"), "pango_layout_set_text"),
            .layoutSetHeight = try symbol(&pango, @FieldType(Engine, "layoutSetHeight"), "pango_layout_set_height"),
            .layoutSetWidth = try symbol(&pango, @FieldType(Engine, "layoutSetWidth"), "pango_layout_set_width"),
            .layoutSetEllipsize = try symbol(&pango, @FieldType(Engine, "layoutSetEllipsize"), "pango_layout_set_ellipsize"),
            .layoutSetSingleParagraph = try symbol(&pango, @FieldType(Engine, "layoutSetSingleParagraph"), "pango_layout_set_single_paragraph_mode"),
            .layoutSetAutoDirection = try symbol(&pango, @FieldType(Engine, "layoutSetAutoDirection"), "pango_layout_set_auto_dir"),
            .layoutSetFont = try symbol(&pango, @FieldType(Engine, "layoutSetFont"), "pango_layout_set_font_description"),
            .layoutGetPixelSize = try symbol(&pango, @FieldType(Engine, "layoutGetPixelSize"), "pango_layout_get_pixel_size"),
            .layoutGetPixelExtents = try symbol(&pango, @FieldType(Engine, "layoutGetPixelExtents"), "pango_layout_get_pixel_extents"),
            .layoutGetLineCount = try symbol(&pango, @FieldType(Engine, "layoutGetLineCount"), "pango_layout_get_line_count"),
            .layoutIsEllipsized = try symbol(&pango, @FieldType(Engine, "layoutIsEllipsized"), "pango_layout_is_ellipsized"),
            .descriptionFromString = try symbol(&pango, @FieldType(Engine, "descriptionFromString"), "pango_font_description_from_string"),
            .descriptionSetAbsoluteSize = try symbol(&pango, @FieldType(Engine, "descriptionSetAbsoluteSize"), "pango_font_description_set_absolute_size"),
            .renderLayout = try symbol(&ft2, @FieldType(Engine, "renderLayout"), "pango_ft2_render_layout"),
            .unref = try symbol(&gobject, @FieldType(Engine, "unref"), "g_object_unref"),
        };
    }
};

var attempted = false;
var engine: ?Engine = null;
var default_context: ?*Object = null;
var default_layout: ?*Object = null;
var bitmap_storage: [1024 * 192]u8 = undefined;

const cache_entry_count = 64;
const cache_slot_bytes = 1024 * 192;
const cache_byte_budget = 2 * 1024 * 1024;
const CacheKey = struct {
    text_hash: [2]u64,
    language_hash: [2]u64,
    max_width: u16,
    font: design.Font,
    lines: u8,
    max_height: u16,
};
const CacheEntry = struct {
    pixels: []u8 = &.{},
    identity: u64 = 0,
    valid: bool = false,
    key: CacheKey = .{
        .text_hash = @splat(0),
        .language_hash = @splat(0),
        .max_width = 0,
        .font = .{ .size = 0 },
        .lines = 0,
        .max_height = 0,
    },
    bitmap_width: u16 = 0,
    bitmap_height: u16 = 0,
    offset_x: u16 = 0,
    offset_y: u16 = 0,
    text_height: u16 = 0,
    reusable_min_width: u16 = 0,
    last_used: u64 = 0,
};
var bitmap_cache: [cache_entry_count]CacheEntry = @splat(.{});
var bitmap_cache_bytes: usize = 0;
var bitmap_cache_clock: u64 = 0;
var bitmap_cache_misses: u64 = 0;

pub fn cacheMissCount() u64 {
    return bitmap_cache_misses;
}

const DescriptionEntry = struct {
    size: u16 = 0,
    weight: design.Weight = .regular,
    family: design.Family = .ui,
    value: ?*FontDescription = null,
};
var descriptions: [24]DescriptionEntry = @splat(.{});

const AttributeEntry = struct { line_height: u16 = 0, value: ?*Object = null };
var attributes: [16]AttributeEntry = @splat(.{});

fn current() ?*Engine {
    if (!attempted) {
        attempted = true;
        engine = Engine.init() catch |err| blk: {
            std.log.warn("Pango initialization failed: {s}", .{@errorName(err)});
            break :blk null;
        };
        if (engine) |*value| {
            default_context = value.createContext(value.font_map);
            if (default_context) |context| default_layout = value.layoutNew(context);
            if (default_context == null or default_layout == null) {
                std.log.warn("Pango retained layout initialization failed", .{});
                engine = null;
            }
        }
    }
    return if (engine) |*value| value else null;
}

fn description(state: *Engine, font: design.Font) ?*FontDescription {
    for (&descriptions) |*entry| {
        if (entry.value != null and entry.size == font.size and entry.weight == font.weight and entry.family == font.family) return entry.value;
    }
    for (&descriptions) |*entry| {
        if (entry.value != null) continue;
        const family: [*:0]const u8 = switch (font.family) {
            .ui => switch (font.weight) {
                .regular => "Inter, Noto Sans",
                .medium => "Inter Medium, Noto Sans Medium",
                .semibold => "Inter SemiBold, Noto Sans SemiBold",
            },
            .display => switch (font.weight) {
                .regular => "Inter, Noto Sans",
                .medium => "Inter Medium, Noto Sans Medium",
                .semibold => "Inter SemiBold, Noto Sans SemiBold",
            },
        };
        const value = state.descriptionFromString(family) orelse return null;
        state.descriptionSetAbsoluteSize(value, @as(f64, @floatFromInt(@as(u32, font.size) * pango_scale)));
        entry.* = .{ .size = font.size, .weight = font.weight, .family = font.family, .value = value };
        return value;
    }
    return null;
}

fn lineHeightAttributes(state: *Engine, line_height: u16) ?*Object {
    if (line_height == 0) return null;
    for (&attributes) |*entry| {
        if (entry.value != null and entry.line_height == line_height) return entry.value;
    }
    for (&attributes) |*entry| {
        if (entry.value != null) continue;
        const list = state.attributeListNew() orelse return null;
        const height = state.lineHeightNew(@as(i32, line_height) * pango_scale) orelse return null;
        state.attributeListInsert(list, height);
        entry.* = .{ .line_height = line_height, .value = list };
        return list;
    }
    return null;
}

fn stringHash(value: []const u8) [2]u64 {
    return .{
        std.hash.Wyhash.hash(0x3c6ef372fe94f82b, value),
        std.hash.Wyhash.hash(0xa54ff53a5f1d36f1, value),
    };
}

fn findBitmap(key: CacheKey) ?usize {
    for (&bitmap_cache, 0..) |*entry, index| {
        var comparable = key;
        if (entry.reusable_min_width != 0 and key.max_width >= entry.reusable_min_width)
            comparable.max_width = entry.key.max_width;
        if (entry.valid and std.meta.eql(entry.key, comparable)) {
            bitmap_cache_clock +%= 1;
            entry.last_used = bitmap_cache_clock;
            return index;
        }
    }
    return null;
}

fn storeBitmap(key: CacheKey, bitmap_width: usize, bitmap_height: usize, text_height: u16) ?usize {
    var left = bitmap_width;
    var top = bitmap_height;
    var right: usize = 0;
    var bottom: usize = 0;
    for (0..bitmap_height) |row| for (0..bitmap_width) |column| {
        if (bitmap_storage[row * bitmap_width + column] == 0) continue;
        left = @min(left, column);
        top = @min(top, row);
        right = @max(right, column + 1);
        bottom = @max(bottom, row + 1);
    };
    if (left == bitmap_width) {
        left = 0;
        top = 0;
    }
    const cropped_width = right - left;
    const cropped_height = bottom - top;
    const byte_count = cropped_width * cropped_height;
    if (byte_count > cache_slot_bytes) return null;
    var target: usize = 0;
    var oldest: u64 = std.math.maxInt(u64);
    for (bitmap_cache, 0..) |entry, index| {
        if (!entry.valid) {
            target = index;
            oldest = 0;
            break;
        }
        if (entry.last_used < oldest) {
            target = index;
            oldest = entry.last_used;
        }
    }
    evictBitmap(target);
    while (bitmap_cache_bytes + byte_count > cache_byte_budget) {
        var victim: ?usize = null;
        for (bitmap_cache, 0..) |entry, index| {
            if (entry.valid and (victim == null or entry.last_used < bitmap_cache[victim.?].last_used)) victim = index;
        }
        evictBitmap(victim orelse return null);
    }
    const storage = std.heap.page_allocator.alloc(u8, byte_count) catch return null;
    bitmap_cache_bytes += byte_count;
    bitmap_cache_clock +%= 1;
    bitmap_cache[target] = .{
        .pixels = storage,
        .identity = bitmap_cache_clock,
        .valid = true,
        .key = key,
        .bitmap_width = @intCast(bitmap_width),
        .bitmap_height = @intCast(cropped_height),
        .offset_x = @intCast(left),
        .offset_y = @intCast(top),
        .text_height = text_height,
        .last_used = bitmap_cache_clock,
    };
    bitmap_cache[target].bitmap_width = @intCast(cropped_width);
    for (0..cropped_height) |row|
        @memcpy(storage[row * cropped_width ..][0..cropped_width], bitmap_storage[(top + row) * bitmap_width + left ..][0..cropped_width]);
    return target;
}

fn evictBitmap(index: usize) void {
    const entry = &bitmap_cache[index];
    bitmap_cache_bytes -= entry.pixels.len;
    std.heap.page_allocator.free(entry.pixels);
    entry.* = .{};
}

fn blendBitmap(clips: []const @import("ui_scene.zig").Rect, pixels: []u32, stride: usize, x: u16, origin_y: u16, bitmap: []const u8, bitmap_width: usize, bitmap_height: usize, packed_color: u32) void {
    const source: PackedColor = @bitCast(packed_color);
    var row: usize = 0;
    while (row < bitmap_height and @as(usize, origin_y) + row < pixels.len / stride) : (row += 1) {
        var column: usize = 0;
        while (column < bitmap_width and @as(usize, x) + column < stride) : (column += 1) {
            if (!@import("damage.zig").containsPixel(clips, x + column, origin_y + row)) continue;
            const alpha = bitmap[row * bitmap_width + column];
            if (alpha == 0) continue;
            const target = (@as(usize, origin_y) + row) * stride + x + column;
            var destination: PackedColor = @bitCast(pixels[target]);
            destination.r = blend(destination.r, source.r, alpha);
            destination.g = blend(destination.g, source.g, alpha);
            destination.b = blend(destination.b, source.b, alpha);
            pixels[target] = @bitCast(destination);
        }
    }
}

pub fn draw(pixels: []u32, stride: usize, x: u16, y: u16, max_width: u16, text: []const u8, packed_color: u32, font: design.Font, language: []const u8, lines: u8, max_height: u16) bool {
    return drawMeasured(pixels, stride, x, y, max_width, text, packed_color, font, language, lines, max_height, null);
}

/// Borrowed cropped coverage for GPU upload. Copy/upload before another text
/// operation can evict this cache slot. Shaping and CPU drawing share one cache.
pub const Mask = struct { bytes: []const u8, width: u16, height: u16, x: u16, y: u16, text_height: u16 };
pub fn rasterize(text: []const u8, font: design.Font, max_width: u16, max_height: u16) ?Mask {
    if (max_width == 0 or max_width > 1024 or max_height == 0 or max_height > 192) return null;
    // Empty destination deliberately performs shaping/cache population only.
    if (!draw(&.{}, 1024, 0, 0, max_width, text, 0, font, "", 1, max_height)) return null;
    const key = CacheKey{ .text_hash = stringHash(text), .language_hash = stringHash(""), .max_width = max_width, .font = font, .lines = 1, .max_height = max_height };
    const index = findBitmap(key) orelse return null;
    const item = bitmap_cache[index];
    return .{ .bytes = item.pixels, .width = item.bitmap_width, .height = item.bitmap_height, .x = item.offset_x, .y = item.offset_y, .text_height = item.text_height };
}

pub fn drawMeasured(pixels: []u32, stride: usize, x: u16, y: u16, max_width: u16, text: []const u8, packed_color: u32, font: design.Font, language: []const u8, lines: u8, max_height: u16, measured_height: ?*u16) bool {
    return drawBlock(pixels, stride, x, y, max_width, text, packed_color, font, language, lines, max_height, measured_height, false, 0);
}

// Centre the measured text and its optional following line as one block.
pub fn drawBlock(pixels: []u32, stride: usize, x: u16, y: u16, max_width: u16, text: []const u8, packed_color: u32, font: design.Font, language: []const u8, lines: u8, max_height: u16, measured_height: ?*u16, centered: bool, tail: u16) bool {
    return drawBlockTo(null, pixels, stride, x, y, max_width, text, packed_color, font, language, lines, max_height, measured_height, centered, tail);
}

pub fn drawBlockTo(sink: ?@import("paint_sink.zig").Sink, pixels: []u32, stride: usize, x: u16, y: u16, max_width: u16, text: []const u8, packed_color: u32, font: design.Font, language: []const u8, lines: u8, max_height: u16, measured_height: ?*u16, centered: bool, tail: u16) bool {
    return drawBlockClipped(sink, &.{}, pixels, stride, x, y, max_width, text, packed_color, font, language, lines, max_height, measured_height, centered, tail);
}

pub fn drawBlockClipped(sink: ?@import("paint_sink.zig").Sink, clips: []const @import("ui_scene.zig").Rect, pixels: []u32, stride: usize, x: u16, y: u16, max_width: u16, text: []const u8, packed_color: u32, font: design.Font, language: []const u8, lines: u8, max_height: u16, measured_height: ?*u16, centered: bool, tail: u16) bool {
    if (measured_height) |out| out.* = 0;
    const state = current() orelse return false;
    if (text.len == 0 or max_width == 0 or x >= stride) return true;
    const cache_key = CacheKey{
        .text_hash = stringHash(text),
        .language_hash = stringHash(language),
        .max_width = max_width,
        .font = font,
        .lines = lines,
        .max_height = max_height,
    };
    if (findBitmap(cache_key)) |index| {
        const cached = bitmap_cache[index];
        if (measured_height) |out| out.* = cached.text_height;
        const origin_y = y + if (centered) (max_height -| (cached.text_height + tail)) / 2 else @as(u16, 0);
        const byte_count = @as(usize, cached.bitmap_width) * cached.bitmap_height;
        if (sink) |output| output.mask(output.context, cached.identity, x + cached.offset_x, origin_y + cached.offset_y, cached.pixels[0..byte_count], cached.bitmap_width, cached.bitmap_height, packed_color) else blendBitmap(clips, pixels, stride, x + cached.offset_x, origin_y + cached.offset_y, cached.pixels[0..byte_count], cached.bitmap_width, cached.bitmap_height, packed_color);
        return true;
    }
    bitmap_cache_misses +%= 1;
    const retained = language.len == 0;
    const context = if (retained) default_context orelse return false else state.createContext(state.font_map) orelse return false;
    defer if (!retained) state.unref(context);
    if (language.len != 0 and language.len < 31) {
        var tag: [32]u8 = @splat(0);
        @memcpy(tag[0..language.len], language);
        if (state.languageFromString(@ptrCast(&tag))) |resolved_language|
            state.contextSetLanguage(context, resolved_language);
    }
    const layout = if (retained) default_layout orelse return false else state.layoutNew(context) orelse return false;
    defer if (!retained) state.unref(layout);
    state.layoutSetFont(layout, description(state, font) orelse return false);
    state.layoutSetText(layout, text.ptr, @intCast(text.len));
    state.layoutSetWidth(layout, @as(i32, max_width) * pango_scale);
    state.layoutSetEllipsize(layout, pango_ellipsize_end);
    state.layoutSetSingleParagraph(layout, if (lines == 1) 1 else 0);
    state.layoutSetHeight(layout, -@as(i32, @max(1, lines)));
    state.layoutSetAutoDirection(layout, 1);
    state.layoutSetAlignment(layout, switch (font.alignment) {
        .start => 0,
        .center => 1,
        .end => 2,
    });
    state.layoutSetAttributes(layout, lineHeightAttributes(state, font.line_height));

    var text_width: i32 = 0;
    var text_height: i32 = 0;
    state.layoutGetPixelSize(layout, &text_width, &text_height);
    if (measured_height) |out| out.* = @intCast(@min(@max(0, text_height), max_height));
    if (text_width <= 0 or text_height <= 0) return true;
    // Pango positions RTL runs against the requested layout width even when the
    // ink extents are narrower. Preserve that width or right-aligned text clips.
    const bitmap_width: usize = max_width;
    const bitmap_height: usize = @min(@as(usize, @intCast(text_height)), @min(max_height, 192));
    @memset(bitmap_storage[0 .. bitmap_width * bitmap_height], 0);
    var bitmap = Bitmap{
        .rows = @intCast(bitmap_height),
        .width = @intCast(bitmap_width),
        .pitch = @intCast(bitmap_width),
        .buffer = &bitmap_storage,
        .num_grays = 256,
        .pixel_mode = ft_pixel_mode_gray,
        .palette_mode = 0,
        .palette = null,
    };
    var ink_offset: i32 = 0;
    if (font.ink_centered) {
        // SAFETY: Pango initializes every field before the rectangle is read.
        var ink: Rectangle = undefined;
        state.layoutGetPixelExtents(layout, &ink, null);
        ink_offset = @divFloor(text_height - ink.height, 2) - ink.y;
    }
    state.renderLayout(&bitmap, layout, 0, ink_offset);

    const origin_y = y + if (centered) (max_height -| (@as(u16, @intCast(text_height)) + tail)) / 2 else @as(u16, 0);
    if (storeBitmap(cache_key, bitmap_width, bitmap_height, @intCast(@min(@max(0, text_height), max_height)))) |index| {
        const ascii = blk: {
            for (text) |byte| if (!std.ascii.isAscii(byte)) break :blk false;
            break :blk true;
        };
        // RTL, alignment, wrapping and ellipsis can make the ink depend on width.
        if (font.alignment == .start and language.len == 0 and ascii and
            state.layoutGetLineCount(layout) == 1 and state.layoutIsEllipsized(layout) == 0)
        {
            // SAFETY: Pango initializes the output rectangle.
            var ink: Rectangle = undefined;
            state.layoutGetPixelExtents(layout, &ink, null);
            const minimum = @max(text_width, ink.x + ink.width) + 1;
            if (minimum > 0 and minimum <= max_width)
                bitmap_cache[index].reusable_min_width = @intCast(minimum);
        }
        const cached = bitmap_cache[index];
        const byte_count = @as(usize, cached.bitmap_width) * cached.bitmap_height;
        if (sink) |output| output.mask(output.context, cached.identity, x + cached.offset_x, origin_y + cached.offset_y, cached.pixels[0..byte_count], cached.bitmap_width, cached.bitmap_height, packed_color) else blendBitmap(clips, pixels, stride, x + cached.offset_x, origin_y + cached.offset_y, cached.pixels[0..byte_count], cached.bitmap_width, cached.bitmap_height, packed_color);
    } else {
        if (sink != null) return false;
        blendBitmap(clips, pixels, stride, x, origin_y, bitmap_storage[0 .. bitmap_width * bitmap_height], bitmap_width, bitmap_height, packed_color);
    }
    return true;
}

const PackedColor = packed struct(u32) { b: u8, g: u8, r: u8, a: u8 };

test "resizing text reuses only width-independent coverage and matches fresh shaping" {
    const count = 1024 * 192;
    const pixels = try std.testing.allocator.alloc(u32, count * 2);
    defer std.testing.allocator.free(pixels);
    defer for (0..cache_entry_count) |index| evictBitmap(index);
    for ([_][]const u8{ "NES", "Game Boy Advance", "Two\nlines", "العربية", "日本語" }) |label| {
        for ([_]design.Alignment{ .start, .center, .end }) |alignment| {
            var font = design.typeface.caption;
            font.alignment = alignment;
            for ([_]u16{ 60, 140, 400, 620 }) |requested_width| {
                for (0..cache_entry_count) |index| evictBitmap(index);
                try std.testing.expect(draw(&.{}, 1024, 0, 0, 600, label, 0, font, "", 2, 120));
                @memset(pixels, 0xff102030);
                try std.testing.expect(draw(pixels[0..count], 1024, 0, 0, requested_width, label, 0xffe0d0c0, font, "", 2, 120));
                for (0..cache_entry_count) |index| evictBitmap(index);
                try std.testing.expect(draw(pixels[count..], 1024, 0, 0, requested_width, label, 0xffe0d0c0, font, "", 2, 120));
                try std.testing.expectEqualSlices(u32, pixels[count..], pixels[0..count]);
            }
        }
    }
    for (0..cache_entry_count) |index| evictBitmap(index);
    const font = design.typeface.caption;
    try std.testing.expect(draw(&.{}, 1024, 0, 0, 600, "NES", 0, font, "", 2, 120));
    const key = CacheKey{ .text_hash = stringHash("NES"), .language_hash = stringHash(""), .max_width = 620, .font = font, .lines = 2, .max_height = 120 };
    try std.testing.expect(findBitmap(key) != null);
}

fn blend(destination: u8, source: u8, alpha: u8) u8 {
    return @intCast((@as(u32, source) * alpha + @as(u32, destination) * (255 - alpha) + 127) / 255);
}

test "coverage cache checks the complete shaping key" {
    for (0..cache_entry_count) |index| evictBitmap(index);
    defer for (0..cache_entry_count) |index| evictBitmap(index);
    const key = CacheKey{ .text_hash = .{ 1, 2 }, .language_hash = .{ 3, 4 }, .max_width = 4, .font = design.typeface.body, .lines = 1, .max_height = 4 };
    @memset(bitmap_storage[0..16], 127);
    const slot = storeBitmap(key, 4, 4, 4).?;
    try std.testing.expectEqual(slot, findBitmap(key).?);
    var changed = key;
    changed.text_hash[1] += 1;
    try std.testing.expectEqual(null, findBitmap(changed));
    changed = key;
    changed.language_hash[1] += 1;
    try std.testing.expectEqual(null, findBitmap(changed));
    changed = key;
    changed.font.size += 1;
    try std.testing.expectEqual(null, findBitmap(changed));
    changed = key;
    changed.lines += 1;
    try std.testing.expectEqual(null, findBitmap(changed));
    changed = key;
    changed.max_height += 1;
    try std.testing.expectEqual(null, findBitmap(changed));
    changed = key;
    changed.max_width += 1;
    try std.testing.expectEqual(null, findBitmap(changed));
    bitmap_cache[slot].reusable_min_width = 4;
    try std.testing.expectEqual(slot, findBitmap(changed).?);
    changed.max_width = 3;
    try std.testing.expectEqual(null, findBitmap(changed));
}

test "coverage cache retains a keyboard working set and respects its byte budget" {
    for (0..cache_entry_count) |index| evictBitmap(index);
    defer for (0..cache_entry_count) |index| evictBitmap(index);
    var key = CacheKey{ .text_hash = @splat(0), .language_hash = @splat(0), .max_width = 4, .font = design.typeface.body, .lines = 1, .max_height = 4 };
    @memset(bitmap_storage[0..16], 127);
    for (0..cache_entry_count) |index| {
        key.text_hash[0] = index;
        try std.testing.expect(storeBitmap(key, 4, 4, 4) != null);
    }
    for (0..cache_entry_count) |index| {
        key.text_hash[0] = index;
        try std.testing.expect(findBitmap(key) != null);
    }
    try std.testing.expectEqual(cache_entry_count * 16, bitmap_cache_bytes);
    @memset(&bitmap_storage, 255);
    for (0..16) |index| {
        key.text_hash[0] = index + cache_entry_count;
        key.max_width = 1024;
        key.max_height = 192;
        try std.testing.expect(storeBitmap(key, 1024, 192, 192) != null);
        try std.testing.expect(bitmap_cache_bytes <= cache_byte_budget);
    }
}
