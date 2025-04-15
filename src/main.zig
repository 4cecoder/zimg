// Import necessary standard library modules
const std = @import("std");
const fs = std.fs;
const io = std.io;
const process = std.process;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const clap = @import("clap");

// Import local modules
const config_module = @import("config.zig");
const Config = config_module.Config;
const image_loader = @import("image_loader.zig");
const utils = @import("utils.zig");
const state_module = @import("state.zig"); // Import state module
const State = state_module.State; // Import State struct
const sdl = @import("sdl_utils.zig"); // Import SDL utils
const upscaler = @import("upscaler.zig"); // Import upscaler

// SDL2 C imports
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

// Constants
const WINDOW_TITLE = "zimg";
const large_directory_threshold: usize = 100; // Consider directories with more than 100 files as large

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create application state using imported State
    var state = state_module.State.init(allocator);
    defer state.deinit();

    // Load configuration (placeholder for TOML parsing)
    const config = config_module.loadConfig(allocator);
    // std.debug.print("Loaded config: max_files={d}, max_images={d}, debug_mode={any}\n", .{config.max_files, config.max_images, config.debug_mode});

    // Process command line arguments (optional directory path)
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    // Use provided path or default to ".", resolving it properly based on system
    var dir_path: []const u8 = undefined;
    var owned_path: bool = false;

    if (args.len > 1) {
        dir_path = args[1];
        owned_path = false;
    } else {
        std.debug.print("No directory provided, defaulting to current directory.\n", .{});

        // First try to get current working directory
        const cwd = process.getCwdAlloc(allocator) catch |err| {
            std.debug.print("Failed to get current working directory: {any}. Using fallback path '.'\n", .{err});
            dir_path = ".";
            owned_path = false;
            return;
        };

        // Check if CWD is an installation directory
        if (std.mem.indexOf(u8, cwd, "/usr/local/") != null or
            std.mem.indexOf(u8, cwd, "/usr/share/") != null)
        {
            std.debug.print("Detected running from installation directory: {s}\n", .{cwd});
            std.debug.print("Please specify a directory with images: zimg /path/to/images\n", .{});
            dir_path = cwd; // Still use the actual directory
        } else {
            dir_path = cwd;
        }
        owned_path = true;
    }

    // This defer statement will be executed at the end of main()
    defer if (owned_path) allocator.free(dir_path);

    // Debug info about the path
    std.debug.print("Using directory path: '{s}'\n", .{dir_path});

    // Load images - loadImages will resolve the path
    try image_loader.loadImages(&state, dir_path, config);

    if (state.image_paths.items.len == 0) {
        // Use the original dir_path for the message
        std.debug.print("No image files found in '{s}'.\n", .{dir_path});
        std.debug.print("Welcome to Zig Image Viewer!\n", .{});
        std.debug.print("Use j/k or arrow keys to navigate between images, q to quit.\n\n", .{});
        return;
    }

    // Initialize SDL2
    try sdl.initSdl();
    defer sdl.deinitSdl();

    // Initialize SDL2_image
    const img_flags = c.IMG_INIT_PNG | c.IMG_INIT_JPG | c.IMG_INIT_TIF | c.IMG_INIT_WEBP | c.IMG_INIT_JXL | c.IMG_INIT_AVIF;
    if ((c.IMG_Init(img_flags) & img_flags) != img_flags) {
        std.debug.print("IMG_Init Warning: Some image formats not supported: {s}\n", .{c.IMG_GetError()});
        // Continue anyway - we can still load some formats
    }
    defer c.IMG_Quit();

    // First load the image to get its dimensions for the window
    var initial_width: i32 = 800;
    var initial_height: i32 = 600;
    try getImageDimensions(&state, &initial_width, &initial_height);

    // Create window with no decorations
    state.window = c.SDL_CreateWindow(WINDOW_TITLE, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, initial_width, initial_height, c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_BORDERLESS);
    if (state.window == null) {
        std.debug.print("SDL_CreateWindow Error: {s}\n", .{c.SDL_GetError()});
        return;
    }

    // Create renderer
    state.renderer = c.SDL_CreateRenderer(state.window, -1, c.SDL_RENDERER_ACCELERATED);
    if (state.renderer == null) {
        std.debug.print("SDL_CreateRenderer Error: {s}\n", .{c.SDL_GetError()});
        return;
    }

    // Load and display the first image
    try sdl.loadCurrentImage(&state);

    // Main event loop
    var running = true;
    while (running) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    running = false;
                },
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_q => {
                            running = false;
                            std.debug.print("Exiting...\n", .{});
                        },
                        c.SDLK_j, c.SDLK_DOWN, c.SDLK_RIGHT => {
                            state.current_image = (state.current_image + 1) % state.image_paths.items.len;
                            try sdl.loadCurrentImage(&state);
                        },
                        c.SDLK_k, c.SDLK_UP, c.SDLK_LEFT => {
                            state.current_image = (state.current_image + state.image_paths.items.len - 1) % state.image_paths.items.len;
                            try sdl.loadCurrentImage(&state);
                        },
                        c.SDLK_u, c.SDLK_2, c.SDLK_3, c.SDLK_4 => {
                            if (state.image_paths.items.len > 0) {
                                const scale: u8 = switch (event.key.keysym.sym) {
                                    c.SDLK_u, c.SDLK_2 => 2,
                                    c.SDLK_3 => 3,
                                    c.SDLK_4 => 4,
                                    else => @panic("unreachable"),
                                };
                                try upscaler.upscaleCurrentImage(&state, scale);
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        // Clear the screen
        sdl.renderClear(state.renderer);

        // Render the current image if loaded
        if (state.texture != null) {
            var img_w: i32 = undefined;
            var img_h: i32 = undefined;
            _ = c.SDL_QueryTexture(state.texture, null, null, &img_w, &img_h);

            // Use the entire window for the image
            var win_w: i32 = undefined;
            var win_h: i32 = undefined;
            _ = c.SDL_GetWindowSize(state.window, &win_w, &win_h);

            // Calculate display position and size to maintain aspect ratio
            const dst_rect = calculateDisplayRect(img_w, img_h, win_w, win_h);
            _ = c.SDL_RenderCopy(state.renderer, state.texture, null, &dst_rect);
        }

        // Present the rendered frame
        sdl.renderPresent(state.renderer);

        // Small delay to prevent CPU overuse
        c.SDL_Delay(16); // ~60 FPS
    }
}

fn getImageDimensions(state: *State, width: *i32, height: *i32) !void {
    if (state.image_paths.items.len == 0) {
        return;
    }

    // Get the path of the first image
    const image_path = state.image_paths.items[state.current_image];

    // Convert image path to C string (null-terminated)
    const path_z = try std.fmt.allocPrintZ(state.allocator, "{s}", .{image_path});
    defer state.allocator.free(path_z);

    // Load the image just to get its dimensions
    const surface = c.IMG_Load(path_z.ptr);
    if (surface == null) {
        return;
    }
    defer c.SDL_FreeSurface(surface);

    // Get image dimensions
    width.* = surface.*.w;
    height.* = surface.*.h;

    // Get screen dimensions and usable area
    var display_info: c.SDL_DisplayMode = undefined;
    var screen_width: i32 = 800;
    var screen_height: i32 = 600;
    var usable_rect: c.SDL_Rect = undefined;

    // Get display information
    if (c.SDL_GetCurrentDisplayMode(0, &display_info) == 0) {
        screen_width = display_info.w;
        screen_height = display_info.h;

        // Get usable display area (accounting for taskbars, docks, etc.)
        if (c.SDL_GetDisplayUsableBounds(0, &usable_rect) == 0) {
            // Use usable bounds instead
            screen_width = usable_rect.w;
            screen_height = usable_rect.h;
        }
    }

    // Account for safety margin (5% on each side)
    const margin_x = @divTrunc(screen_width * 5, 100);
    const margin_y = @divTrunc(screen_height * 5, 100);
    const max_width = screen_width - (margin_x * 2);
    const max_height = screen_height - (margin_y * 2);

    // Scale image if needed
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

fn calculateDisplayRect(img_w: i32, img_h: i32, win_w: i32, win_h: i32) c.SDL_Rect {
    var dst_rect: c.SDL_Rect = undefined;

    // Calculate aspect ratios
    const img_aspect: f32 = @as(f32, @floatFromInt(img_w)) / @as(f32, @floatFromInt(img_h));
    const win_aspect: f32 = @as(f32, @floatFromInt(win_w)) / @as(f32, @floatFromInt(win_h));

    if (img_aspect > win_aspect) {
        // Image is wider relative to window
        dst_rect.w = win_w;
        dst_rect.h = @as(i32, @intFromFloat(@as(f32, @floatFromInt(win_w)) / img_aspect));
        dst_rect.x = 0;
        dst_rect.y = @divTrunc(win_h - dst_rect.h, 2);
    } else {
        // Image is taller relative to window
        dst_rect.h = win_h;
        dst_rect.w = @as(i32, @intFromFloat(@as(f32, @floatFromInt(win_h)) * img_aspect));
        dst_rect.x = @divTrunc(win_w - dst_rect.w, 2);
        dst_rect.y = 0;
    }

    return dst_rect;
}

fn isLargeDirectory(path: []const u8) !bool {
    var dir = fs.cwd().openDir(path, .{ .iterate = true }) catch {
        // If we can't open the directory, it's not a directory or we don't have permissions
        // In either case, it's not a large directory
        return false;
    };
    defer dir.close();

    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |_| {
        count += 1;
        if (count > large_directory_threshold) {
            return true;
        }
    }

    return false;
}

fn debug_print_directory_contents(path: []const u8, debug_mode: bool) !void {
    if (!debug_mode) return;

    // Check if directory is large before printing contents
    const directory_is_large = try isLargeDirectory(path);

    std.debug.print("Scanning directory: {s}\n", .{path});

    if (directory_is_large) {
        std.debug.print("Large directory detected (>{d} files). Skipping detailed debug output.\n", .{large_directory_threshold});
        return;
    }

    const result = try process.Child.exec(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "ls", "-la", path },
        .max_output_bytes = 4096,
    });
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    std.debug.print("Directory contents:\n{s}\n", .{result.stdout});
}
