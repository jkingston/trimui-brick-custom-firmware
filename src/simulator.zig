// SPDX-License-Identifier: GPL-2.0-only
// Desktop host for the exact model, layout and software renderer used on-device.
const std = @import("std");
const catalog = @import("catalog.zig");
const input = @import("input.zig");
const model = @import("model.zig");
const overlay = @import("overlay.zig");
const render = @import("render.zig");
const retroarch = @import("retroarch.zig");
const ui = @import("ui.zig");

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
const WaitEventFn = *const fn (*Event, i32) callconv(.c) i32;
const GetErrorFn = *const fn () callconv(.c) [*:0]const u8;

const Sdl = struct {
    library: std.DynLib,
    init: InitFn,
    quit: QuitFn,
    createWindow: CreateWindowFn,
    destroyWindow: DestroyWindowFn,
    setWindowSize: SetWindowSizeFn,
    getDisplayDpi: GetDisplayDpiFn,
    createRenderer: CreateRendererFn,
    destroyRenderer: DestroyRendererFn,
    renderSetLogicalSize: RenderSetLogicalSizeFn,
    createTexture: CreateTextureFn,
    destroyTexture: DestroyTextureFn,
    updateTexture: UpdateTextureFn,
    renderClear: RenderClearFn,
    renderCopy: RenderCopyFn,
    renderPresent: RenderPresentFn,
    waitEvent: WaitEventFn,
    getError: GetErrorFn,

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
            .createWindow = try loadSymbol(&library, CreateWindowFn, "SDL_CreateWindow"),
            .destroyWindow = try loadSymbol(&library, DestroyWindowFn, "SDL_DestroyWindow"),
            .setWindowSize = try loadSymbol(&library, SetWindowSizeFn, "SDL_SetWindowSize"),
            .getDisplayDpi = try loadSymbol(&library, GetDisplayDpiFn, "SDL_GetDisplayDPI"),
            .createRenderer = try loadSymbol(&library, CreateRendererFn, "SDL_CreateRenderer"),
            .destroyRenderer = try loadSymbol(&library, DestroyRendererFn, "SDL_DestroyRenderer"),
            .renderSetLogicalSize = try loadSymbol(&library, RenderSetLogicalSizeFn, "SDL_RenderSetLogicalSize"),
            .createTexture = try loadSymbol(&library, CreateTextureFn, "SDL_CreateTexture"),
            .destroyTexture = try loadSymbol(&library, DestroyTextureFn, "SDL_DestroyTexture"),
            .updateTexture = try loadSymbol(&library, UpdateTextureFn, "SDL_UpdateTexture"),
            .renderClear = try loadSymbol(&library, RenderClearFn, "SDL_RenderClear"),
            .renderCopy = try loadSymbol(&library, RenderCopyFn, "SDL_RenderCopy"),
            .renderPresent = try loadSymbol(&library, RenderPresentFn, "SDL_RenderPresent"),
            .waitEvent = try loadSymbol(&library, WaitEventFn, "SDL_WaitEventTimeout"),
            .getError = try loadSymbol(&library, GetErrorFn, "SDL_GetError"),
        };
    }

    fn close(self: *Sdl) void {
        self.library.close();
    }
};

const sdl_init_video: u32 = 0x00000020;
const sdl_window_position_centered: i32 = 0x2fff0000;
const sdl_window_resizable: u32 = 0x00000020;
const sdl_renderer_software: u32 = 0x00000001;
const sdl_renderer_accelerated: u32 = 0x00000002;
const sdl_renderer_present_vsync: u32 = 0x00000004;
const sdl_texture_access_streaming: i32 = 1;
const sdl_pixel_format_argb8888: u32 = 0x16362004;
const sdl_quit: u32 = 0x100;
const sdl_key_down: u32 = 0x300;
const sdl_key_release: u32 = 0x301;

const sdl_key_return: i32 = 13;
const sdl_key_escape: i32 = 27;
const sdl_key_up: i32 = 1073741906;
const sdl_key_down_arrow: i32 = 1073741905;
const sdl_key_left: i32 = 1073741904;
const sdl_key_right: i32 = 1073741903;

const WindowSize = struct { width: i32, height: i32 };

fn physicalWindowSize(sdl: *const Sdl) WindowSize {
    var diagonal_dpi: f32 = 96;
    var horizontal_dpi: f32 = 96;
    var vertical_dpi: f32 = 96;
    _ = sdl.getDisplayDpi(0, &diagonal_dpi, &horizontal_dpi, &vertical_dpi);
    if (horizontal_dpi < 50 or horizontal_dpi > 800) horizontal_dpi = 96;
    if (vertical_dpi < 50 or vertical_dpi > 800) vertical_dpi = horizontal_dpi;
    return .{
        .width = @intFromFloat(@round(horizontal_dpi * 2.56)),
        .height = @intFromFloat(@round(vertical_dpi * 1.92)),
    };
}

fn failSdl(sdl: *const Sdl, operation: []const u8) !void {
    std.log.err("{s}: {s}", .{ operation, std.mem.span(sdl.getError()) });
    return error.SdlFailure;
}

fn drawTree(sdl: *const Sdl, renderer: *Renderer, texture: *Texture, pixels: []u32, tree: *const ui.Tree) !void {
    (render.Surface{ .pixels = pixels }).render(tree);
    if (sdl.updateTexture(texture, null, pixels.ptr, render.width * @sizeOf(u32)) != 0)
        return failSdl(sdl, "SDL_UpdateTexture");
    if (sdl.renderClear(renderer) != 0) return failSdl(sdl, "SDL_RenderClear");
    if (sdl.renderCopy(renderer, texture, null, null) != 0) return failSdl(sdl, "SDL_RenderCopy");
    sdl.renderPresent(renderer);
}

fn actionForKey(key: i32) ?input.Action {
    return switch (key) {
        sdl_key_up, 'w' => .up,
        sdl_key_down_arrow, 's' => .down,
        sdl_key_left, 'a' => .left,
        sdl_key_right, 'd' => .right,
        sdl_key_return, 'z' => .select,
        sdl_key_escape, 'x' => .back,
        'h' => .menu,
        'v' => .view,
        else => null,
    };
}

pub fn main(init: std.process.Init) !void {
    var data_root: ?[]const u8 = null;
    var library_check: ?[]const u8 = null;
    var physical_size = true;
    var overlay_visible = false;
    var walkthrough = false;
    var arguments = std.process.Args.Iterator.init(init.minimal.args);
    _ = arguments.next();
    while (arguments.next()) |argument| {
        if (std.mem.eql(u8, argument, "--data-root")) {
            data_root = arguments.next() orelse return error.MissingDataRoot;
        } else if (std.mem.eql(u8, argument, "--library-check")) {
            library_check = arguments.next() orelse return error.MissingSnapshotDirectory;
        } else if (std.mem.eql(u8, argument, "--pixels")) {
            physical_size = false;
        } else if (std.mem.eql(u8, argument, "--physical")) {
            physical_size = true;
        } else if (std.mem.eql(u8, argument, "--overlay")) {
            overlay_visible = true;
        } else if (std.mem.eql(u8, argument, "--walkthrough")) {
            overlay_visible = true;
            walkthrough = true;
        } else return error.UnknownArgument;
    }

    var sdl = try Sdl.open();
    defer sdl.close();
    if (sdl.init(sdl_init_video) != 0) return failSdl(&sdl, "SDL_Init");
    defer sdl.quit();

    const physical = physicalWindowSize(&sdl);
    const initial_size = if (physical_size) physical else WindowSize{ .width = render.width, .height = render.height };
    const window = sdl.createWindow(
        "Brick UI Simulator - M game menu, arrows, Z/A, X/B, P scale",
        sdl_window_position_centered,
        sdl_window_position_centered,
        initial_size.width,
        initial_size.height,
        sdl_window_resizable,
    ) orelse return failSdl(&sdl, "SDL_CreateWindow");
    defer sdl.destroyWindow(window);
    const renderer = sdl.createRenderer(window, -1, sdl_renderer_accelerated | sdl_renderer_present_vsync) orelse
        sdl.createRenderer(window, -1, sdl_renderer_software) orelse return failSdl(&sdl, "SDL_CreateRenderer");
    defer sdl.destroyRenderer(renderer);
    if (sdl.renderSetLogicalSize(renderer, render.width, render.height) != 0)
        return failSdl(&sdl, "SDL_RenderSetLogicalSize");
    const texture = sdl.createTexture(renderer, sdl_pixel_format_argb8888, sdl_texture_access_streaming, render.width, render.height) orelse
        return failSdl(&sdl, "SDL_CreateTexture");
    defer sdl.destroyTexture(texture);

    const pixels = try init.gpa.alloc(u32, render.width * render.height);
    defer init.gpa.free(pixels);
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    var state = model.Model{};
    if (data_root) |root| {
        const absolute = try std.Io.Dir.cwd().realPathFileAlloc(init.io, root, arena.allocator());
        state.games = try catalog.discover(init.io, arena.allocator(), absolute);
    }
    var game_overlay = overlay.Model{};
    game_overlay.appearance = state.settings.appearance;
    var tree = if (overlay_visible) game_overlay.tree() else state.tree();
    try drawTree(&sdl, renderer, texture, pixels, &tree);

    if (library_check) |directory| {
        try std.Io.Dir.cwd().createDirPath(init.io, directory);
        tree = state.tree();
        try drawTree(&sdl, renderer, texture, pixels, &tree);
        try @import("main.zig").writePpm(init.io, try std.Io.Dir.path.join(arena.allocator(), &.{ directory, "library.ppm" }), pixels);
        for (state.games, 0..) |game, index| {
            if (state.selected != index) return error.SelectionMismatch;
            tree = state.tree();
            try drawTree(&sdl, renderer, texture, pixels, &tree);
            if (index == 0) try @import("main.zig").writePpm(init.io, try std.Io.Dir.path.join(arena.allocator(), &.{ directory, "detail.ppm" }), pixels);
            _ = state.apply(.select);
            if (state.takeLaunch() != index) return error.LaunchMismatch;
            const argv = retroarch.arguments(&game);
            std.log.info("Launch intent: {s} / {s}", .{ argv[4], game.rom_path });
            tree = state.tree();
            try drawTree(&sdl, renderer, texture, pixels, &tree);
            _ = state.apply(.down);
        }
        if (state.games.len > 0 and state.selected != state.games.len - 1) return error.BoundaryMismatch;
        _ = state.apply(.up);
        tree = state.tree();
        try drawTree(&sdl, renderer, texture, pixels, &tree);
        try @import("main.zig").writePpm(init.io, try std.Io.Dir.path.join(arena.allocator(), &.{ directory, "library-last.ppm" }), pixels);
        std.log.info("Simulator library check passed: {d} games (launch intents only)", .{state.games.len});
        return;
    }

    if (walkthrough) {
        const Step = struct { wait_ms: u32, action: input.Action };
        const steps = [_]Step{
            .{ .wait_ms = 1300, .action = .down },
            .{ .wait_ms = 750, .action = .select },
            .{ .wait_ms = 1250, .action = .down },
            .{ .wait_ms = 700, .action = .select },
            .{ .wait_ms = 1200, .action = .down },
            .{ .wait_ms = 700, .action = .down },
            .{ .wait_ms = 700, .action = .down },
            .{ .wait_ms = 700, .action = .up },
            .{ .wait_ms = 700, .action = .back },
            .{ .wait_ms = 750, .action = .down },
            .{ .wait_ms = 700, .action = .select },
            .{ .wait_ms = 1200, .action = .down },
            .{ .wait_ms = 750, .action = .right },
            .{ .wait_ms = 750, .action = .down },
            .{ .wait_ms = 750, .action = .right },
            .{ .wait_ms = 750, .action = .down },
            .{ .wait_ms = 750, .action = .right },
            .{ .wait_ms = 900, .action = .back },
        };
        for (steps) |step| {
            try std.Io.sleep(init.io, .fromMilliseconds(step.wait_ms), .awake);
            _ = game_overlay.apply(step.action);
            tree = game_overlay.tree();
            try drawTree(&sdl, renderer, texture, pixels, &tree);
            if (game_overlay.takeCommand()) |command|
                std.log.info("Overlay command: {s}", .{@tagName(command)});
        }
        try std.Io.sleep(init.io, .fromMilliseconds(1400), .awake);
        return;
    }

    var motion: @import("shelf_motion.zig").Motion = .{};
    var repeat: @import("input_repeat.zig").Controller = .{};
    var was_animating = false;
    while (true) {
        const now = std.Io.Timestamp.now(init.io, .awake).toMilliseconds();
        const animating = !overlay_visible and state.page == .games and state.library_view == .shelf and motion.active(now);
        const repeat_timeout = repeat.timeout(now);
        const timeout = if (animating) (if (repeat_timeout < 0) @import("design.zig").motion.frame_ms else @min(@import("design.zig").motion.frame_ms, repeat_timeout)) else if (was_animating) 0 else repeat_timeout;
        // SAFETY: event is inspected only when SDL reports an initialized event.
        var event: Event = undefined;
        const received = sdl.waitEvent(&event, timeout) != 0;
        const timestamp = std.Io.Timestamp.now(init.io, .awake).toMilliseconds();
        var action: ?input.Action = repeat.due(timestamp);
        var changed = animating or was_animating;
        was_animating = animating;
        if (received) {
            if (event.event_type == sdl_quit) break;
            if (event.event_type == sdl_key_release) {
                if (actionForKey(event.key.keysym.sym)) |released| repeat.release(released);
            } else if (event.event_type == sdl_key_down and event.key.repeat == 0) {
                const key = event.key.keysym.sym;
                if (key == 'p') {
                    physical_size = !physical_size;
                    const size = if (physical_size) physical else WindowSize{ .width = render.width, .height = render.height };
                    sdl.setWindowSize(window, size.width, size.height);
                    changed = true;
                } else if (key == 'm') {
                    overlay_visible = !overlay_visible;
                    if (overlay_visible) game_overlay = .{};
                    repeat.reset();
                    changed = true;
                } else if (actionForKey(key)) |pressed| {
                    action = pressed;
                    if (pressed == .up or pressed == .down or pressed == .left or pressed == .right) repeat.press(pressed, timestamp);
                }
            }
        }
        if (action) |pressed| {
            if (overlay_visible) {
                changed = game_overlay.apply(pressed) or changed;
                if (game_overlay.takeCommand()) |command| {
                    std.log.info("Overlay command: {s}", .{@tagName(command)});
                    switch (command) {
                        .resume_game, .exit_game, .load_state => overlay_visible = false,
                        .save_state => game_overlay.notice = "Simulator: no save written",
                        .apply_performance => {},
                    }
                    changed = true;
                }
            } else {
                const previous = state.selected;
                changed = state.apply(pressed) or changed;
                if (state.page == .games and state.library_view == .shelf and previous != state.selected)
                    motion.retarget(@as(i32, @intCast(state.selected)) - @as(i32, @intCast(previous)), timestamp);
                if (state.takeLaunch()) |index| {
                    const argv = retroarch.arguments(&state.games[index]);
                    std.log.info("Launch intent: {s} / {s}", .{ argv[4], state.games[index].rom_path });
                }
            }
        }
        if (changed) {
            game_overlay.appearance = state.settings.appearance;
            tree = if (overlay_visible) game_overlay.tree() else state.treeWithShelfOffset(motion.offset(timestamp));
            try drawTree(&sdl, renderer, texture, pixels, &tree);
        }
    }
}
