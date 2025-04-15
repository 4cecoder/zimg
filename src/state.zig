const std = @import("std");
const Allocator = std.mem.Allocator;

// SDL2 C imports (needed for window, renderer, texture types)
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h"); // Keep IMG for consistency, though not strictly needed here
});

pub const State = struct {
    image_paths: std.ArrayList([]const u8),
    current_image: usize = 0,
    allocator: Allocator, // Store the allocator used to create this state
    window: ?*c.SDL_Window = null,
    renderer: ?*c.SDL_Renderer = null,
    texture: ?*c.SDL_Texture = null,

    // Include max_images here if needed by loadImagesFromDir, or pass config there
    // max_images: usize, // Example: if moved from Config

    pub fn init(allocator: Allocator) State {
        return State{
            .image_paths = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
            // .max_images = config.max_images, // Example: Initialize from config if needed
        };
    }

    pub fn deinit(self: *State) void {
        // Free allocated memory for image paths
        for (self.image_paths.items) |path| {
            self.allocator.free(path);
        }
        self.image_paths.deinit();

        // Cleanup SDL resources - Note: This assumes State owns these resources.
        // Consider moving SDL cleanup to where SDL is initialized/deinitialized (e.g., sdl_utils.zig)
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
        // The allocator itself is likely owned by main, so don't deinit it here.
    }
};
