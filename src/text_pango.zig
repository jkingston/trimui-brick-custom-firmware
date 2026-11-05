// SPDX-License-Identifier: GPL-2.0-only
// Runtime-loaded PangoFT2 backend: UTF-8, shaping, bidi and font fallback.
const std = @import("std");

const Object = opaque {};
const FontDescription = opaque {};
const pango_scale = 1024;
const pango_ellipsize_end = 3;
const ft_pixel_mode_gray = 2;

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
    layoutNew: *const fn (*Object) callconv(.c) ?*Object,
    layoutSetText: *const fn (*Object, [*]const u8, i32) callconv(.c) void,
    layoutSetWidth: *const fn (*Object, i32) callconv(.c) void,
    layoutSetEllipsize: *const fn (*Object, i32) callconv(.c) void,
    layoutSetSingleParagraph: *const fn (*Object, i32) callconv(.c) void,
    layoutSetAutoDirection: *const fn (*Object, i32) callconv(.c) void,
    layoutSetFont: *const fn (*Object, *FontDescription) callconv(.c) void,
    layoutGetPixelSize: *const fn (*Object, *i32, *i32) callconv(.c) void,
    descriptionFromString: *const fn ([*:0]const u8) callconv(.c) ?*FontDescription,
    descriptionSetAbsoluteSize: *const fn (*FontDescription, f64) callconv(.c) void,
    descriptionFree: *const fn (*FontDescription) callconv(.c) void,
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
            .layoutNew = try symbol(&pango, @FieldType(Engine, "layoutNew"), "pango_layout_new"),
            .layoutSetText = try symbol(&pango, @FieldType(Engine, "layoutSetText"), "pango_layout_set_text"),
            .layoutSetWidth = try symbol(&pango, @FieldType(Engine, "layoutSetWidth"), "pango_layout_set_width"),
            .layoutSetEllipsize = try symbol(&pango, @FieldType(Engine, "layoutSetEllipsize"), "pango_layout_set_ellipsize"),
            .layoutSetSingleParagraph = try symbol(&pango, @FieldType(Engine, "layoutSetSingleParagraph"), "pango_layout_set_single_paragraph_mode"),
            .layoutSetAutoDirection = try symbol(&pango, @FieldType(Engine, "layoutSetAutoDirection"), "pango_layout_set_auto_dir"),
            .layoutSetFont = try symbol(&pango, @FieldType(Engine, "layoutSetFont"), "pango_layout_set_font_description"),
            .layoutGetPixelSize = try symbol(&pango, @FieldType(Engine, "layoutGetPixelSize"), "pango_layout_get_pixel_size"),
            .descriptionFromString = try symbol(&pango, @FieldType(Engine, "descriptionFromString"), "pango_font_description_from_string"),
            .descriptionSetAbsoluteSize = try symbol(&pango, @FieldType(Engine, "descriptionSetAbsoluteSize"), "pango_font_description_set_absolute_size"),
            .descriptionFree = try symbol(&pango, @FieldType(Engine, "descriptionFree"), "pango_font_description_free"),
            .renderLayout = try symbol(&ft2, @FieldType(Engine, "renderLayout"), "pango_ft2_render_layout"),
            .unref = try symbol(&gobject, @FieldType(Engine, "unref"), "g_object_unref"),
        };
    }
};

var attempted = false;
var engine: ?Engine = null;
var bitmap_storage: [1024 * 96]u8 = undefined;

fn current() ?*Engine {
    if (!attempted) {
        attempted = true;
        engine = Engine.init() catch |err| blk: {
            std.log.warn("Pango initialization failed: {s}", .{@errorName(err)});
            break :blk null;
        };
    }
    return if (engine) |*value| value else null;
}

fn pixelSize(scale: u8) u16 {
    return switch (scale) {
        2 => 28,
        3 => 36,
        4 => 48,
        else => 60,
    };
}

pub fn draw(pixels: []u32, stride: usize, x: u16, y: u16, max_width: u16, text: []const u8, packed_color: u32, scale: u8, language: []const u8) bool {
    const state = current() orelse return false;
    if (text.len == 0 or max_width == 0 or x >= stride) return true;
    const context = state.createContext(state.font_map) orelse return false;
    defer state.unref(context);
    if (language.len != 0 and language.len < 31) {
        var tag: [32]u8 = @splat(0);
        @memcpy(tag[0..language.len], language);
        if (state.languageFromString(@ptrCast(&tag))) |resolved_language|
            state.contextSetLanguage(context, resolved_language);
    }
    const layout = state.layoutNew(context) orelse return false;
    defer state.unref(layout);
    const family: [*:0]const u8 = if (scale >= 4) "Noto Sans SemiBold" else "Noto Sans";
    const description = state.descriptionFromString(family) orelse return false;
    defer state.descriptionFree(description);
    state.descriptionSetAbsoluteSize(description, @as(f64, @floatFromInt(pixelSize(scale) * pango_scale)));
    state.layoutSetFont(layout, description);
    state.layoutSetText(layout, text.ptr, @intCast(text.len));
    state.layoutSetWidth(layout, @as(i32, max_width) * pango_scale);
    state.layoutSetEllipsize(layout, pango_ellipsize_end);
    state.layoutSetSingleParagraph(layout, 1);
    state.layoutSetAutoDirection(layout, 1);

    var text_width: i32 = 0;
    var text_height: i32 = 0;
    state.layoutGetPixelSize(layout, &text_width, &text_height);
    if (text_width <= 0 or text_height <= 0) return true;
    // Pango positions RTL runs against the requested layout width even when the
    // ink extents are narrower. Preserve that width or right-aligned text clips.
    const bitmap_width: usize = max_width;
    const bitmap_height: usize = @min(@as(usize, @intCast(text_height)), 96);
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
    state.renderLayout(&bitmap, layout, 0, 0);

    const source: PackedColor = @bitCast(packed_color);
    var row: usize = 0;
    while (row < bitmap_height and @as(usize, y) + row < pixels.len / stride) : (row += 1) {
        var column: usize = 0;
        while (column < bitmap_width and @as(usize, x) + column < stride) : (column += 1) {
            const alpha = bitmap_storage[row * bitmap_width + column];
            if (alpha == 0) continue;
            const target = (@as(usize, y) + row) * stride + x + column;
            var destination: PackedColor = @bitCast(pixels[target]);
            destination.r = blend(destination.r, source.r, alpha);
            destination.g = blend(destination.g, source.g, alpha);
            destination.b = blend(destination.b, source.b, alpha);
            pixels[target] = @bitCast(destination);
        }
    }
    return true;
}

const PackedColor = packed struct(u32) { b: u8, g: u8, r: u8, a: u8 };

fn blend(destination: u8, source: u8, alpha: u8) u8 {
    return @intCast((@as(u32, source) * alpha + @as(u32, destination) * (255 - alpha) + 127) / 255);
}
