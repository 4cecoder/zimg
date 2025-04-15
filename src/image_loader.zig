const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const io = std.io; // Added for promptUserForDirectory

// Import necessary types/functions from other modules
// const main = @import("main.zig"); // Removed circular import
const State = @import("state.zig").State; // Import State directly
const Config = @import("config.zig").Config;
const utils = @import("utils.zig"); // Import utils
const isImageFile = utils.isImageFile; // Get the function

pub fn loadImages(state: *State, path_to_scan: []const u8, config: Config) !void {
    const allocator = state.allocator;
    var absolute_path_buffer: [fs.max_path_bytes]u8 = undefined;

    // Store the original path for user messages
    const original_path = path_to_scan;

    // Always resolve the path received from main
    const absolute_dir_path = fs.realpath(path_to_scan, &absolute_path_buffer) catch |err| {
        std.debug.print("Error resolving path '{s}': {any}\n", .{ path_to_scan, err });
        return err;
    };

    std.debug.print("Resolved path '{s}' to absolute path: '{s}'\n", .{ path_to_scan, absolute_dir_path });

    // Check if we resolved to the installation directory and it was a relative path
    if (mem.eql(u8, path_to_scan, ".") and
        (mem.indexOf(u8, absolute_dir_path, "/usr/local/share/zimg") != null or
            mem.indexOf(u8, absolute_dir_path, "/usr/share/zimg") != null))
    {
        std.debug.print("Warning: Current directory resolved to installation directory.\n", .{});
        std.debug.print("This likely means you're running from the installation directory.\n", .{});
        std.debug.print("To view images, please use: zimg /path/to/your/images\n", .{});
    }

    // Open the directory using the absolute path
    var dir = std.fs.openDirAbsolute(absolute_dir_path, .{ .iterate = true }) catch {
        return error.OpenDirFailed;
    };
    defer dir.close();

    // Iterate through directory entries to find images and subdirectories
    var total_files: usize = 0;
    var image_files: usize = 0;
    var directories: usize = 0;
    const max_files_limit: usize = config.max_files; // Use config value
    var subdirs_with_images = std.ArrayList([]const u8).init(allocator);
    defer {
        for (subdirs_with_images.items) |path| {
            allocator.free(path);
        }
        subdirs_with_images.deinit();
    }

    // Scan current directory for images
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        total_files += 1;

        if (total_files > max_files_limit) {
            std.debug.print("Reached file processing limit of {d}. Stopping scan to prevent overload.\n", .{max_files_limit});
            break;
        }

        if (entry.kind == .directory) {
            directories += 1;
            if (subdirs_with_images.items.len < config.max_subdirs) { // Use config value
                const subdir_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ absolute_dir_path, entry.name });
                // Recursive scan with depth limit
                try scanSubdirectory(subdir_path, &subdirs_with_images, allocator, config.max_depth, config.debug_mode); // Pass debug_mode
            }
        } else if (isImageFile(entry.name, config.debug_mode)) { // Use imported function
            image_files += 1;
            // Note: Accessing state.max_images directly here, consider passing config instead if State doesn't hold it.
            if (state.image_paths.items.len < config.max_images) {
                const full_path = try std.fmt.allocPrint(state.allocator, "{s}/{s}", .{ absolute_dir_path, entry.name });
                try state.image_paths.append(full_path);
            }
        } else {
            // Not an image file
        }

        if (total_files % config.batch_size == 0) { // Use config value
            // Optional debug print
        }
    }

    // If no images found in current directory but subdirectories with images exist, prompt user
    if (image_files == 0 and subdirs_with_images.items.len > 0) {
        _ = std.debug.print("No images found in '{s}', but found {d} subdirectories with images.\n", .{ original_path, subdirs_with_images.items.len });
        const chosen_dir = try promptUserForDirectory(allocator, subdirs_with_images.items);
        for (state.image_paths.items) |path| {
            allocator.free(path);
        }
        state.image_paths.clearRetainingCapacity();
        try loadImagesFromDir(state, chosen_dir, config.debug_mode, config.max_images); // Pass debug_mode and max_images
        allocator.free(chosen_dir);
    } else if (image_files == 0 and subdirs_with_images.items.len == 0) {
        _ = std.debug.print("No image files or subdirectories with images found in '{s}' (scanned {d} total files, found {d} directories).\n", .{ original_path, total_files, directories });
    } else {
        _ = std.debug.print("Found {d} images out of {d} total files in '{s}'.\n", .{ image_files, total_files, original_path });
        if (image_files > config.suggestion_threshold) {
            _ = std.debug.print("Suggestion: Use arrow keys (left/right) or j/k to navigate through the images.\n", .{});
        }
    }
}

fn scanSubdirectory(dir_path: []const u8, subdirs_with_images: *std.ArrayList([]const u8), allocator: Allocator, depth_limit: usize, debug_mode: bool) !void {
    if (depth_limit == 0) {
        allocator.free(dir_path);
        return;
    }

    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch {
        allocator.free(dir_path);
        return;
    };
    defer dir.close();

    var has_images_in_subdir = false;
    var current_dir_has_images = false;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and isImageFile(entry.name, debug_mode)) {
            current_dir_has_images = true;
        } else if (entry.kind == .directory) {
            const subdir_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
            // Recurse first
            try scanSubdirectory(subdir_path, subdirs_with_images, allocator, depth_limit - 1, debug_mode);
            // Check if the recursion added the subdir_path to the list
            // This indicates the subdir (or one of its children) had images.
            // This logic might need refinement depending on exact desired behavior.
            if (subdirs_with_images.items.len > 0 and mem.eql(u8, subdirs_with_images.items[subdirs_with_images.items.len - 1], subdir_path)) {
                has_images_in_subdir = true;
            } else {
                // If the subdir_path wasn't added, it was freed during recursion, do nothing here.
            }
        }
    }

    // Now decide whether to keep or free dir_path
    if (current_dir_has_images) {
        // Add the current directory if it directly contains images
        try subdirs_with_images.append(dir_path);
    } else if (has_images_in_subdir) {
        // Keep the path if a subdirectory had images, but don't add it again if it was already added by recursion.
        // This path might be needed by the caller, so don't free it yet.
        // The current structure adds the *parent* dir that contains image-containing subdirs
        // Let's keep this behavior for now.
        // If we want *only* the direct image-containing folders, this needs change.
        try subdirs_with_images.append(dir_path);
        // Or simply `_ = dir_path;` // Keep path allocated, don't add
    } else {
        // Free the path if neither this dir nor any subdir had images
        allocator.free(dir_path);
    }
}

fn hasImages(dir_path: []const u8, debug_mode: bool) !bool {
    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch |err| {
        std.debug.print("Error opening subdirectory '{s}': {any}\n", .{ dir_path, err });
        return false;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and isImageFile(entry.name, debug_mode)) { // Use imported function
            if (debug_mode) std.debug.print("Image found in {s}: {s}\n", .{ dir_path, entry.name });
            return true; // Found one, return immediately
        }
    }
    return false;
}

fn promptUserForDirectory(allocator: Allocator, dirs: [][]const u8) ![]const u8 {
    const reset = "\x1B[0m";
    const cyan = "\x1B[36m";
    const yellow = "\x1B[33m";
    const green = "\x1B[32m";

    std.debug.print("\n{0s}=== Image Directory Selection ==={1s}\n", .{ cyan, reset });
    std.debug.print("{0s}No images found directly, but we detected {1d} subdirectories that might contain images.{2s}\n", .{ yellow, dirs.len, reset });
    std.debug.print("{0s}Please select a directory to view:{1s}\n\n", .{ yellow, reset });
    for (dirs, 1..) |dir, i| {
        std.debug.print("  {0s}[{1d}]{2s} {3s}\n\n", .{ green, i, reset, dir });
    }
    std.debug.print("{0s}Enter the number of your choice: {1s}", .{ yellow, reset });

    const stdin = std.io.getStdIn().reader(); // Use imported io
    var buf: [10]u8 = undefined;
    const input = try stdin.readUntilDelimiterOrEof(&buf, '\n');
    if (input == null or input.?.len == 0) {
        std.debug.print("{0s}Invalid input, defaulting to first directory.{1s}\n", .{ yellow, reset });
        std.debug.print("{0s}===============================\n{1s}", .{ cyan, reset });
        return try allocator.dupe(u8, dirs[0]);
    }

    const choice = std.fmt.parseInt(usize, input.?, 10) catch {
        std.debug.print("{0s}Invalid number, defaulting to first directory.{1s}\n", .{ yellow, reset });
        std.debug.print("{0s}===============================\n{1s}", .{ cyan, reset });
        return try allocator.dupe(u8, dirs[0]);
    };

    if (choice < 1 or choice > dirs.len) {
        std.debug.print("{0s}Choice out of range, defaulting to first directory.{1s}\n", .{ yellow, reset });
        std.debug.print("{0s}===============================\n{1s}", .{ cyan, reset });
        return try allocator.dupe(u8, dirs[0]);
    }

    std.debug.print("{0s}===============================\n{1s}", .{ cyan, reset });
    return try allocator.dupe(u8, dirs[choice - 1]);
}

fn loadImagesFromDir(state: *State, dir_path: []const u8, debug_mode: bool, max_images: usize) !void {
    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch {
        // Don't free dir_path here, it was duplicated by the caller (promptUserForDirectory)
        // The caller is responsible for freeing it.
        std.debug.print("Error opening chosen directory: {s}\n", .{dir_path});
        return;
    };
    defer dir.close();

    var image_files: usize = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and isImageFile(entry.name, debug_mode)) { // Use imported function
            image_files += 1;
            if (state.image_paths.items.len < max_images) { // Use passed max_images
                const full_path = try std.fmt.allocPrint(state.allocator, "{s}/{s}", .{ dir_path, entry.name });
                try state.image_paths.append(full_path);
                if (debug_mode) std.debug.print("Added image from chosen dir: {s}\n", .{entry.name});
            } else {
                std.debug.print("Reached image limit ({d}), skipping remaining images in {s}.\n", .{ max_images, dir_path });
                break;
            }
        }
    }
    std.debug.print("Loaded {d} images from chosen directory '{s}'.\n", .{ image_files, dir_path });
}
