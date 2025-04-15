const std = @import("std");
const State = @import("state.zig").State;

// SDL2 C imports
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

pub const SdlError = error{
    InitFailed,
    ImageInitFailed,
    WindowCreationFailed,
    RendererCreationFailed,
    LoadImageFailed,
    TextureCreationFailed,
};

const WINDOW_TITLE = "zimg"; // Consider making this configurable

pub fn initSdl() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL_Init Error: {s}\n", .{c.SDL_GetError()});
        return SdlError.InitFailed;
    }

    const img_flags = c.IMG_INIT_PNG | c.IMG_INIT_JPG | c.IMG_INIT_TIF | c.IMG_INIT_WEBP | c.IMG_INIT_JXL | c.IMG_INIT_AVIF;
    if ((c.IMG_Init(img_flags) & img_flags) != img_flags) {
        std.debug.print("IMG_Init Warning: Some image formats not supported: {s}\n", .{c.IMG_GetError()});
        // Don't return error, just warn
    }
}

pub fn deinitSdl() void {
    c.IMG_Quit();
    c.SDL_Quit();
}

pub fn createWindowAndRenderer(state: *State) !void {
    var initial_width: i32 = 800;
    var initial_height: i32 = 600;

    // Only try to get dimensions if there are images
    if (state.image_paths.items.len > 0) {
        getImageDimensions(state, &initial_width, &initial_height) catch |err| {
            std.debug.print("Warning: Failed to get initial image dimensions: {any}. Using default 800x600.\n", .{err});
            // Continue with default dimensions
        };
    }

    state.window = c.SDL_CreateWindow(WINDOW_TITLE, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, initial_width, initial_height, c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_BORDERLESS);
    if (state.window == null) {
        std.debug.print("SDL_CreateWindow Error: {s}\n", .{c.SDL_GetError()});
        return SdlError.WindowCreationFailed;
    }

    state.renderer = c.SDL_CreateRenderer(state.window, -1, c.SDL_RENDERER_ACCELERATED);
    if (state.renderer == null) {
        std.debug.print("SDL_CreateRenderer Error: {s}\n", .{c.SDL_GetError()});
        // Clean up window if renderer fails
        c.SDL_DestroyWindow(state.window);
        state.window = null;
        return SdlError.RendererCreationFailed;
    }
}

// Get image dimensions and calculate appropriate window size
fn getImageDimensions(state: *State, width: *i32, height: *i32) !void {
    if (state.image_paths.items.len == 0) {
        return; // Should not happen if called correctly, but safety check
    }

    const image_path = state.image_paths.items[state.current_image];
    const path_z = try std.fmt.allocPrintZ(state.allocator, "{s}", .{image_path});
    defer state.allocator.free(path_z);

    const surface = c.IMG_Load(path_z.ptr) orelse {
        std.debug.print("IMG_Load failed for dimensions ('{s}'): {s}\n", .{ image_path, c.IMG_GetError() });
        return SdlError.LoadImageFailed;
    };
    defer c.SDL_FreeSurface(surface);

    width.* = surface.*.w;
    height.* = surface.*.h;

    // Calculate max dimensions based on usable screen area
    var display_info: c.SDL_DisplayMode = undefined;
    var usable_rect: c.SDL_Rect = .{ .x = 0, .y = 0, .w = 800, .h = 600 }; // Default

    if (c.SDL_GetCurrentDisplayMode(0, &display_info) == 0) {
        usable_rect.w = display_info.w;
        usable_rect.h = display_info.h;
        _ = c.SDL_GetDisplayUsableBounds(0, &usable_rect); // Ignore error, use full screen if fails
    }

    const margin_x = @divTrunc(usable_rect.w * 5, 100);
    const margin_y = @divTrunc(usable_rect.h * 5, 100);
    const max_width = usable_rect.w - (margin_x * 2);
    const max_height = usable_rect.h - (margin_y * 2);

    // Scale down if needed
    if (width.* > max_width) {
        const ratio = @as(f32, @floatFromInt(max_width)) / @as(f32, @floatFromInt(width.*));
        width.* = max_width;
        height.* = @intFromFloat(@as(f32, @floatFromInt(height.*)) * ratio);
    }
    if (height.* > max_height) {
        const ratio = @as(f32, @floatFromInt(max_height)) / @as(f32, @floatFromInt(height.*));
        height.* = max_height;
        width.* = @intFromFloat(@as(f32, @floatFromInt(width.*)) * ratio);
    }
}

// Load the current image into the state's texture and resize window
pub fn loadCurrentImage(state: *State) !void {
    if (state.texture != null) {
        c.SDL_DestroyTexture(state.texture);
        state.texture = null;
    }

    if (state.image_paths.items.len == 0 or state.renderer == null or state.window == null) {
        return; // Cannot load if no images or SDL components are missing
    }

    const image_path = state.image_paths.items[state.current_image];
    const path_z = try std.fmt.allocPrintZ(state.allocator, "{s}", .{image_path});
    defer state.allocator.free(path_z);

    const surface = c.IMG_Load(path_z.ptr) orelse {
        std.debug.print("IMG_Load Error ('{s}'): {s}\n", .{ image_path, c.IMG_GetError() });
        return SdlError.LoadImageFailed;
    };
    defer c.SDL_FreeSurface(surface);

    state.texture = c.SDL_CreateTextureFromSurface(state.renderer, surface) orelse {
        std.debug.print("SDL_CreateTextureFromSurface Error: {s}\n", .{c.SDL_GetError()});
        return SdlError.TextureCreationFailed;
    };

    var img_w: i32 = surface.*.w;
    var img_h: i32 = surface.*.h;

    // Calculate max dimensions based on usable screen area
    var display_info: c.SDL_DisplayMode = undefined;
    var usable_rect: c.SDL_Rect = .{ .x = 0, .y = 0, .w = 800, .h = 600 }; // Default
    var display_index: i32 = 0;

    if (state.window != null) {
        display_index = c.SDL_GetWindowDisplayIndex(state.window);
        if (display_index < 0) display_index = 0;
    }

    if (c.SDL_GetCurrentDisplayMode(display_index, &display_info) == 0) {
        usable_rect.w = display_info.w;
        usable_rect.h = display_info.h;
        _ = c.SDL_GetDisplayUsableBounds(display_index, &usable_rect); // Ignore error
    }

    const margin_x = @divTrunc(usable_rect.w * 5, 100);
    const margin_y = @divTrunc(usable_rect.h * 5, 100);
    const max_width = usable_rect.w - (margin_x * 2);
    const max_height = usable_rect.h - (margin_y * 2);

    std.debug.print("Image dimensions: {d}x{d}, Usable Screen: {d}x{d} ({d},{d}), Max size: {d}x{d}\n", .{ img_w, img_h, usable_rect.w, usable_rect.h, usable_rect.x, usable_rect.y, max_width, max_height });

    // Scale down if needed
    var scaled = false;
    if (img_w > max_width) {
        const ratio = @as(f32, @floatFromInt(max_width)) / @as(f32, @floatFromInt(img_w));
        img_w = max_width;
        img_h = @intFromFloat(@as(f32, @floatFromInt(img_h)) * ratio);
        scaled = true;
    }
    if (img_h > max_height) {
        const ratio = @as(f32, @floatFromInt(max_height)) / @as(f32, @floatFromInt(img_h));
        img_h = max_height;
        img_w = @intFromFloat(@as(f32, @floatFromInt(img_w)) * ratio);
        scaled = true;
    }
    if (scaled) {
        std.debug.print("Scaled image to: {d}x{d}\n", .{ img_w, img_h });
    }

    // Resize and reposition window
    c.SDL_SetWindowSize(state.window, img_w, img_h);
    const window_x = usable_rect.x + @divTrunc(usable_rect.w - img_w, 2);
    const window_y = usable_rect.y + @divTrunc(usable_rect.h - img_h, 2);
    c.SDL_SetWindowPosition(state.window, window_x, window_y);
}

// Calculate the destination rectangle to render the image centered with aspect ratio
pub fn calculateDisplayRect(img_w: i32, img_h: i32, win_w: i32, win_h: i32) c.SDL_Rect {
    var dst_rect: c.SDL_Rect = undefined;
    const img_aspect = @as(f32, @floatFromInt(img_w)) / @as(f32, @floatFromInt(img_h));
    const win_aspect = @as(f32, @floatFromInt(win_w)) / @as(f32, @floatFromInt(win_h));

    if (img_aspect > win_aspect) {
        dst_rect.w = win_w;
        dst_rect.h = @intFromFloat(@as(f32, @floatFromInt(win_w)) / img_aspect);
        dst_rect.x = 0;
        dst_rect.y = @divTrunc(win_h - dst_rect.h, 2);
    } else {
        dst_rect.h = win_h;
        dst_rect.w = @intFromFloat(@as(f32, @floatFromInt(win_h)) * img_aspect);
        dst_rect.x = @divTrunc(win_w - dst_rect.w, 2);
        dst_rect.y = 0;
    }
    return dst_rect;
}

pub fn renderClear(renderer: ?*c.SDL_Renderer) void {
    if (renderer) |r| {
        _ = c.SDL_SetRenderDrawColor(r, 0, 0, 0, 255); // Black background
        _ = c.SDL_RenderClear(r);
    }
}

pub fn renderImage(state: *State) void {
    if (state.renderer) |renderer| {
        if (state.texture) |texture| {
            var img_w: i32 = undefined;
            var img_h: i32 = undefined;
            _ = c.SDL_QueryTexture(texture, null, null, &img_w, &img_h);

            var win_w: i32 = undefined;
            var win_h: i32 = undefined;
            if (state.window) |window| {
                _ = c.SDL_GetWindowSize(window, &win_w, &win_h);
            } else {
                return;
            } // Cannot render without window

            const dst_rect = calculateDisplayRect(img_w, img_h, win_w, win_h);
            _ = c.SDL_RenderCopy(renderer, texture, null, &dst_rect);
        }
    }
}

pub fn renderPresent(renderer: ?*c.SDL_Renderer) void {
    if (renderer) |r| {
        c.SDL_RenderPresent(r);
    }
}
