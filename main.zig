// Import necessary standard library modules
const std = @import("std");
const fs = std.fs;
const io = std.io;
const process = std.process;
const mem = std.mem;
const Allocator = std.mem.Allocator;

// SDL2 C imports
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

// Constants
const WINDOW_TITLE = "zimg";

// Image viewer state
const State = struct {
    image_paths: std.ArrayList([]const u8),
    current_image: usize = 0,
    allocator: std.mem.Allocator,
    window: ?*c.SDL_Window = null,
    renderer: ?*c.SDL_Renderer = null,
    texture: ?*c.SDL_Texture = null,

    fn init(allocator: std.mem.Allocator) State {
        return State{
            .image_paths = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *State) void {
        // Free allocated memory
        for (self.image_paths.items) |path| {
            self.allocator.free(path);
        }
        self.image_paths.deinit();

        // Cleanup SDL resources
        if (self.texture != null) {
            c.SDL_DestroyTexture(self.texture);
            self.texture = null;
        }
        if (self.renderer != null) {
            c.SDL_DestroyRenderer(self.renderer);
            self.renderer = null;
        }
        if (self.window != null) {
            c.SDL_DestroyWindow(self.window);
            self.window = null;
        }
    }
};

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create application state
    var state = State.init(allocator);
    defer state.deinit();

    // Process command line arguments (optional directory path)
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);
    const dir_path = if (args.len > 1) args[1] else ".";

    // Load images from the directory
    try loadImages(&state, dir_path);

    if (state.image_paths.items.len == 0) {
        std.debug.print("No image files found in '{s}'.\n", .{dir_path});
        std.debug.print("Welcome to Zig Image Viewer!\n", .{});
        std.debug.print("Use j/k or arrow keys to navigate between images, q to quit.\n\n", .{});
        return;
    }

    // Initialize SDL2
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL_Init Error: {s}\n", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_Quit();

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
    try loadCurrentImage(&state);

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
                            try loadCurrentImage(&state);
                        },
                        c.SDLK_k, c.SDLK_UP, c.SDLK_LEFT => {
                            state.current_image = (state.current_image + state.image_paths.items.len - 1) % state.image_paths.items.len;
                            try loadCurrentImage(&state);
                        },
                        c.SDLK_u => {
                            // Upscale the current image
                            if (state.image_paths.items.len > 0) {
                                const current_path = state.image_paths.items[state.current_image];
                                std.debug.print("Upscaling image: {s}\n", .{current_path});

                                // Call upscale function with default scale factor of 2
                                upscaleCurrentImage(&state, 2) catch |err| {
                                    std.debug.print("Error upscaling image: {any}\n", .{err});
                                };
                            }
                        },
                        c.SDLK_2 => {
                            // Upscale with scale factor 2
                            if (state.image_paths.items.len > 0) {
                                upscaleCurrentImage(&state, 2) catch |err| {
                                    std.debug.print("Error upscaling image: {any}\n", .{err});
                                };
                            }
                        },
                        c.SDLK_3 => {
                            // Upscale with scale factor 3
                            if (state.image_paths.items.len > 0) {
                                upscaleCurrentImage(&state, 3) catch |err| {
                                    std.debug.print("Error upscaling image: {any}\n", .{err});
                                };
                            }
                        },
                        c.SDLK_4 => {
                            // Upscale with scale factor 4
                            if (state.image_paths.items.len > 0) {
                                upscaleCurrentImage(&state, 4) catch |err| {
                                    std.debug.print("Error upscaling image: {any}\n", .{err});
                                };
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        // Clear the screen
        _ = c.SDL_SetRenderDrawColor(state.renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(state.renderer);

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
        c.SDL_RenderPresent(state.renderer);

        // Small delay to prevent CPU overuse
        c.SDL_Delay(16); // ~60 FPS
    }
}

fn loadImages(state: *State, dir_path: []const u8) !void {
    // Open the directory
    var dir = try fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    // Iterate through directory entries
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        // Simple check for image files by extension
        if (isImageFile(entry.name)) {
            const full_path = try std.fmt.allocPrint(state.allocator, "{s}/{s}", .{ dir_path, entry.name });
            try state.image_paths.append(full_path);
        }
    }

    if (state.image_paths.items.len == 0) {
        std.debug.print("No image files found in '{s}'.\n", .{dir_path});
    } else {
        std.debug.print("Found {d} images.\n", .{state.image_paths.items.len});
    }
}

fn isImageFile(filename: []const u8) bool {
    const extensions = [_][]const u8{ ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tiff", ".webp" };

    for (extensions) |ext| {
        if (mem.endsWith(u8, filename, ext)) {
            return true;
        }
    }

    return false;
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

fn loadCurrentImage(state: *State) !void {
    // Clear previous texture if any
    if (state.texture != null) {
        c.SDL_DestroyTexture(state.texture);
        state.texture = null;
    }

    if (state.image_paths.items.len == 0) {
        return;
    }

    // Get the path of the current image
    const image_path = state.image_paths.items[state.current_image];

    // Convert image path to C string (null-terminated)
    const path_z = try std.fmt.allocPrintZ(state.allocator, "{s}", .{image_path});
    defer state.allocator.free(path_z);

    // First try loading with IMG_Load to get more detailed error information
    const surface = c.IMG_Load(path_z.ptr);
    if (surface == null) {
        std.debug.print("IMG_Load Error: {s}\n", .{c.IMG_GetError()});
        return;
    }
    defer c.SDL_FreeSurface(surface);

    // Now create texture from surface
    state.texture = c.SDL_CreateTextureFromSurface(state.renderer, surface);
    if (state.texture == null) {
        std.debug.print("SDL_CreateTextureFromSurface Error: {s}\n", .{c.SDL_GetError()});
        return;
    }

    // Get original image dimensions
    var img_w: i32 = surface.*.w;
    var img_h: i32 = surface.*.h;

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
        var display_index: i32 = 0;
        if (state.window != null) {
            display_index = c.SDL_GetWindowDisplayIndex(state.window);
        }

        if (c.SDL_GetDisplayUsableBounds(display_index, &usable_rect) == 0) {
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

    std.debug.print("Image dimensions: {d}x{d}, Screen: {d}x{d}, Max size: {d}x{d}\n", .{ img_w, img_h, screen_width, screen_height, max_width, max_height });

    // Scale down image if it's larger than the available space
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

    // Resize window to match image dimensions
    c.SDL_SetWindowSize(state.window, img_w, img_h);

    // Center window on screen
    const window_x = @divTrunc(screen_width - img_w, 2) + usable_rect.x;
    const window_y = @divTrunc(screen_height - img_h, 2) + usable_rect.y;
    c.SDL_SetWindowPosition(state.window, window_x, window_y);
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

fn upscaleCurrentImage(state: *State, scale: u8) !void {
    if (state.image_paths.items.len == 0) {
        return;
    }

    // Get the path of the current image
    const input_path = state.image_paths.items[state.current_image];

    // Generate output path by adding "_upscaledx{scale}" before the extension
    var output_path_buf: [fs.max_path_bytes]u8 = undefined;
    var output_path: []u8 = undefined;

    // Find the last dot in the path for the extension
    const last_dot = std.mem.lastIndexOf(u8, input_path, ".");
    if (last_dot != null) {
        // Insert the upscale suffix before the extension
        const base = input_path[0..last_dot.?];
        const ext = input_path[last_dot.?..];
        output_path = try std.fmt.bufPrint(&output_path_buf, "{s}_upscaledx{d}{s}", .{ base, scale, ext });
    } else {
        // No extension found, just append the suffix
        output_path = try std.fmt.bufPrint(&output_path_buf, "{s}_upscaledx{d}", .{ input_path, scale });
    }

    std.debug.print("Upscaling image: {s} -> {s} (scale: {d})\n", .{ input_path, output_path, scale });

    // Check for upscaler script existence
    var script_path: []const u8 = "upscale/main.py";
    var upscale_dir: []const u8 = "upscale";
    var install_dir_script_exists = false;

    // Check if we're running from an installed location
    // Try the standard install path first
    const install_paths = [_][]const u8{
        "/usr/local/share/zimg/upscale/main.py",
        "/usr/share/zimg/upscale/main.py",
    };

    for (install_paths) |path| {
        if (fs.cwd().access(path, .{})) {
            script_path = path;
            upscale_dir = std.fs.path.dirname(path) orelse "upscale";
            install_dir_script_exists = true;
            std.debug.print("Found upscaler script at: {s}\n", .{script_path});
            break;
        } else |_| {
            // Continue checking other paths
        }
    }

    // Check for virtual environment in upscale directory
    var use_venv = false;
    var venv_path: []const u8 = "";

    // Check for common virtual environment paths
    const venv_candidates = if (install_dir_script_exists)
        [_][]const u8{
            try std.fmt.allocPrint(state.allocator, "{s}/venv", .{upscale_dir}),
            try std.fmt.allocPrint(state.allocator, "{s}/.venv", .{upscale_dir}),
            "venv",
            ".venv",
        }
    else
        [_][]const u8{
            "upscale/venv",
            "upscale/.venv",
            "venv",
            ".venv",
        };

    defer {
        if (install_dir_script_exists) {
            for (venv_candidates[0..2]) |candidate| {
                state.allocator.free(candidate);
            }
        }
    }

    for (venv_candidates) |candidate| {
        var venv_dir = fs.cwd().openDir(candidate, .{}) catch continue;
        venv_dir.close();

        // Found a valid venv directory
        use_venv = true;
        venv_path = candidate;
        std.debug.print("Found virtual environment at: {s}\n", .{venv_path});
        break;
    }

    // Create command arguments
    var argv = std.ArrayList([]const u8).init(state.allocator);
    defer argv.deinit();

    if (use_venv) {
        // Check OS to determine activation approach
        const builtin = @import("builtin");
        if (builtin.os.tag == .windows) {
            // Windows activation
            try argv.append("cmd.exe");
            try argv.append("/c");

            const activate_path = try std.fmt.allocPrint(state.allocator, "{s}\\Scripts\\activate.bat && python {s}", .{ venv_path, script_path });
            defer state.allocator.free(activate_path);
            try argv.append(activate_path);
        } else {
            // Unix-like activation (macOS, Linux)
            try argv.append("sh");
            try argv.append("-c");

            const activate_cmd = try std.fmt.allocPrint(state.allocator, "source {s}/bin/activate && python {s} \"{s}\" \"{s}\" --scale {d}", .{ venv_path, script_path, input_path, output_path, scale });
            defer state.allocator.free(activate_cmd);
            try argv.append(activate_cmd);
        }
    } else {
        // Fallback to system Python if no venv found
        try argv.append("python");
        try argv.append(script_path);
        try argv.append(input_path);
        try argv.append(output_path);
        try argv.append("--scale");
        try argv.append(try std.fmt.allocPrint(state.allocator, "{d}", .{scale}));
    }

    // Create and configure the child process
    var child = std.process.Child.init(argv.items, state.allocator);

    // Set up stdio options
    child.stdin_behavior = .Close;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    // Run the command
    try child.spawn();

    // Get process result
    const result = try child.wait();

    if (result.Exited != 0) {
        // Something went wrong, try to read stderr
        const stderr = try child.stderr.?.reader().readAllAlloc(state.allocator, 10 * 1024);
        defer state.allocator.free(stderr);
        std.debug.print("Python upscaler error: {s}\n", .{stderr});
        return error.UpscalingFailed;
    }

    // Add the upscaled image to the list
    const owned_output_path = try state.allocator.dupe(u8, output_path);
    try state.image_paths.append(owned_output_path);

    // Set the current image to the newly upscaled one
    state.current_image = state.image_paths.items.len - 1;

    // Reload the image for display
    try loadCurrentImage(state);

    std.debug.print("Upscaling complete!\n", .{});
}
