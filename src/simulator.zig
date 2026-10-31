// SPDX-License-Identifier: GPL-2.0-only
// Desktop host for the exact model, layout and software renderer used on-device.
const std = @import("std");
const model = @import("model.zig");
const render = @import("render.zig");

const Window = opaque {};
const Renderer = opaque {};
const Texture = opaque {};
const Rect = extern struct { x: i32, y: i32, width: i32, height: i32 };
const Keysym = extern struct { scancode: i32, sym: i32, modifiers: u16, unused: u32 };
const KeyboardEvent = extern struct {
    event_type: u32,
    timestamp: u32,
    window_id: u32,
    state: u8,
    repeat: u8,
    padding: [2]u8,
    keysym: Keysym,
};
const Event = extern union {
    event_type: u32,
    key: KeyboardEvent,
    padding: [56]u8,
};

const InitFn = *const fn (u32) callconv(.c) i32;
const QuitFn = *const fn () callconv(.c) void;
const CreateWindowFn = *const fn ([*:0]const u8, i32, i32, i32, i32, u32) callconv(.c) ?*Window;
const DestroyWindowFn = *const fn (*Window) callconv(.c) void;
const SetWindowSizeFn = *const fn (*Window, i32, i32) callconv(.c) void;
const GetDisplayDpiFn = *const fn (i32, ?*f32, ?*f32, ?*f32) callconv(.c) i32;
const CreateRendererFn = *const fn (*Window, i32, u32) callconv(.c) ?*Renderer;
const DestroyRendererFn = *const fn (*Renderer) callconv(.c) void;
const RenderSetLogicalSizeFn = *const fn (*Renderer, i32, i32) callconv(.c) i32;
const CreateTextureFn = *const fn (*Renderer, u32, i32, i32, i32) callconv(.c) ?*Texture;
const DestroyTextureFn = *const fn (*Texture) callconv(.c) void;
const UpdateTextureFn = *const fn (*Texture, ?*const Rect, *const anyopaque, i32) callconv(.c) i32;
const RenderClearFn = *const fn (*Renderer) callconv(.c) i32;
const RenderCopyFn = *const fn (*Renderer, *Texture, ?*const Rect, ?*const Rect) callconv(.c) i32;
const RenderPresentFn = *const fn (*Renderer) callconv(.c) void;
const WaitEventFn = *const fn (*Event) callconv(.c) i32;
const GetErrorFn = *const fn () callconv(.c) [*:0]const u8;

const Sdl = struct {
    library: std.DynLib,
    init: InitFn,
    quit: QuitFn,
    create_window: CreateWindowFn,
    destroy_window: DestroyWindowFn,
    set_window_size: SetWindowSizeFn,
    get_display_dpi: GetDisplayDpiFn,
    create_renderer: CreateRendererFn,
    destroy_renderer: DestroyRendererFn,
    render_set_logical_size: RenderSetLogicalSizeFn,
    create_texture: CreateTextureFn,
    destroy_texture: DestroyTextureFn,
    update_texture: UpdateTextureFn,
    render_clear: RenderClearFn,
    render_copy: RenderCopyFn,
    render_present: RenderPresentFn,
    wait_event: WaitEventFn,
    get_error: GetErrorFn,

    fn loadSymbol(library: *std.DynLib, comptime T: type, comptime name: [:0]const u8) !T {
        return library.lookup(T, name) orelse error.MissingSdlSymbol;
    }

    fn open() !Sdl {
        var library = std.DynLib.open("libSDL2-2.0.so.0") catch try std.DynLib.open("libSDL2.so");
        errdefer library.close();
        return .{
            .library = library,
            .init = try loadSymbol(&library, InitFn, "SDL_Init"),
            .quit = try loadSymbol(&library, QuitFn, "SDL_Quit"),
            .create_window = try loadSymbol(&library, CreateWindowFn, "SDL_CreateWindow"),
            .destroy_window = try loadSymbol(&library, DestroyWindowFn, "SDL_DestroyWindow"),
            .set_window_size = try loadSymbol(&library, SetWindowSizeFn, "SDL_SetWindowSize"),
            .get_display_dpi = try loadSymbol(&library, GetDisplayDpiFn, "SDL_GetDisplayDPI"),
            .create_renderer = try loadSymbol(&library, CreateRendererFn, "SDL_CreateRenderer"),
            .destroy_renderer = try loadSymbol(&library, DestroyRendererFn, "SDL_DestroyRenderer"),
            .render_set_logical_size = try loadSymbol(&library, RenderSetLogicalSizeFn, "SDL_RenderSetLogicalSize"),
            .create_texture = try loadSymbol(&library, CreateTextureFn, "SDL_CreateTexture"),
            .destroy_texture = try loadSymbol(&library, DestroyTextureFn, "SDL_DestroyTexture"),
            .update_texture = try loadSymbol(&library, UpdateTextureFn, "SDL_UpdateTexture"),
            .render_clear = try loadSymbol(&library, RenderClearFn, "SDL_RenderClear"),
            .render_copy = try loadSymbol(&library, RenderCopyFn, "SDL_RenderCopy"),
            .render_present = try loadSymbol(&library, RenderPresentFn, "SDL_RenderPresent"),
            .wait_event = try loadSymbol(&library, WaitEventFn, "SDL_WaitEvent"),
            .get_error = try loadSymbol(&library, GetErrorFn, "SDL_GetError"),
        };
    }

    fn close(self: *Sdl) void {
        self.library.close();
    }
};

const SDL_INIT_VIDEO: u32 = 0x00000020;
const SDL_WINDOWPOS_CENTERED: i32 = 0x2fff0000;
const SDL_WINDOW_RESIZABLE: u32 = 0x00000020;
const SDL_RENDERER_SOFTWARE: u32 = 0x00000001;
const SDL_RENDERER_ACCELERATED: u32 = 0x00000002;
const SDL_RENDERER_PRESENTVSYNC: u32 = 0x00000004;
const SDL_TEXTUREACCESS_STREAMING: i32 = 1;
const SDL_PIXELFORMAT_ARGB8888: u32 = 0x16362004;
const SDL_QUIT: u32 = 0x100;
const SDL_KEYDOWN: u32 = 0x300;

const SDLK_RETURN: i32 = 13;
const SDLK_ESCAPE: i32 = 27;
const SDLK_UP: i32 = 1073741906;
const SDLK_DOWN: i32 = 1073741905;
const SDLK_LEFT: i32 = 1073741904;
const SDLK_RIGHT: i32 = 1073741903;
const SDLK_F1: i32 = 1073741882;
const SDLK_F2: i32 = 1073741883;

const WindowSize = struct { width: i32, height: i32 };

fn physicalWindowSize(sdl: *const Sdl) WindowSize {
    var diagonal_dpi: f32 = 96;
    var horizontal_dpi: f32 = 96;
    var vertical_dpi: f32 = 96;
    _ = sdl.get_display_dpi(0, &diagonal_dpi, &horizontal_dpi, &vertical_dpi);
    if (horizontal_dpi < 50 or horizontal_dpi > 800) horizontal_dpi = 96;
    if (vertical_dpi < 50 or vertical_dpi > 800) vertical_dpi = horizontal_dpi;
    return .{
        .width = @intFromFloat(@round(horizontal_dpi * 2.56)),
        .height = @intFromFloat(@round(vertical_dpi * 1.92)),
    };
}

fn failSdl(sdl: *const Sdl, operation: []const u8) !void {
    std.debug.print("{s}: {s}\n", .{ operation, std.mem.span(sdl.get_error()) });
    return error.SdlFailure;
}

fn draw(sdl: *const Sdl, renderer: *Renderer, texture: *Texture, pixels: []u32, state: *const model.Model) !void {
    var tree = state.tree();
    (render.Surface{ .pixels = pixels }).render(&tree);
    if (sdl.update_texture(texture, null, pixels.ptr, render.width * @sizeOf(u32)) != 0)
        return failSdl(sdl, "SDL_UpdateTexture");
    if (sdl.render_clear(renderer) != 0) return failSdl(sdl, "SDL_RenderClear");
    if (sdl.render_copy(renderer, texture, null, null) != 0) return failSdl(sdl, "SDL_RenderCopy");
    sdl.render_present(renderer);
}

fn actionForKey(key: i32) ?model.Action {
    return switch (key) {
        SDLK_UP, 'w' => .up,
        SDLK_DOWN, 's' => .down,
        SDLK_LEFT, 'a' => .left,
        SDLK_RIGHT, 'd' => .right,
        SDLK_RETURN, 'z' => .confirm,
        SDLK_ESCAPE, 'x' => .back,
        'h' => .home,
        SDLK_F1 => .switcher,
        'o' => .options,
        'f' => .favorite,
        else => null,
    };
}

fn directPage(key: i32) ?model.Page {
    return switch (key) {
        '1' => .systems,
        '2' => .games,
        '3' => .game_detail,
        '4' => .quick_menu,
        '5' => .checkpoints,
        '6' => .game_settings,
        '7' => .storage,
        '8' => .empty_library,
        '9' => .save_data,
        '0' => .save_conflict,
        SDLK_F2 => .storage,
        else => null,
    };
}

pub fn main(init: std.process.Init) !void {
    var physical_size = true;
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    _ = arguments.next();
    while (arguments.next()) |argument| {
        if (std.mem.eql(u8, argument, "--pixels")) physical_size = false else if (!std.mem.eql(u8, argument, "--physical")) return error.UnknownArgument;
    }

    var sdl = try Sdl.open();
    defer sdl.close();
    if (sdl.init(SDL_INIT_VIDEO) != 0) return failSdl(&sdl, "SDL_Init");
    defer sdl.quit();

    const physical = physicalWindowSize(&sdl);
    const initial_size = if (physical_size) physical else WindowSize{ .width = render.width, .height = render.height };
    const window = sdl.create_window(
        "Brick UI Simulator - P physical/pixels, arrows, Z/A, X/B, 1-0 screens",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        initial_size.width,
        initial_size.height,
        SDL_WINDOW_RESIZABLE,
    ) orelse return failSdl(&sdl, "SDL_CreateWindow");
    defer sdl.destroy_window(window);
    const renderer = sdl.create_renderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC) orelse
        sdl.create_renderer(window, -1, SDL_RENDERER_SOFTWARE) orelse return failSdl(&sdl, "SDL_CreateRenderer");
    defer sdl.destroy_renderer(renderer);
    if (sdl.render_set_logical_size(renderer, render.width, render.height) != 0)
        return failSdl(&sdl, "SDL_RenderSetLogicalSize");
    const texture = sdl.create_texture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, render.width, render.height) orelse
        return failSdl(&sdl, "SDL_CreateTexture");
    defer sdl.destroy_texture(texture);

    const pixels = try init.gpa.alloc(u32, render.width * render.height);
    defer init.gpa.free(pixels);
    var state = model.Model.preview(.games, 3);
    try draw(&sdl, renderer, texture, pixels, &state);

    while (true) {
        var event: Event = undefined;
        if (sdl.wait_event(&event) == 0) return failSdl(&sdl, "SDL_WaitEvent");
        if (event.event_type == SDL_QUIT) break;
        if (event.event_type != SDL_KEYDOWN or event.key.repeat != 0) continue;
        const key = event.key.keysym.sym;
        var changed = false;
        if (key == 'p') {
            physical_size = !physical_size;
            const size = if (physical_size) physical else WindowSize{ .width = render.width, .height = render.height };
            sdl.set_window_size(window, size.width, size.height);
            changed = true;
        } else if (directPage(key)) |page| {
            state = model.Model.preview(page, if (page == .games) 3 else 0);
            changed = true;
        } else if (actionForKey(key)) |action| {
            changed = state.apply(action);
        }
        if (changed) try draw(&sdl, renderer, texture, pixels, &state);
    }
}
