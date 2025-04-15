const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const process = std.process;

pub fn isImageFile(filename: []const u8, debug_mode: bool) bool {
    const extensions = [_][]const u8{ ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tiff", ".webp", ".PNG", ".JPG", ".JPEG", ".GIF", ".BMP", ".TIFF", ".WEBP" };

    if (std.mem.indexOf(u8, filename, "-") != null) {
        for (extensions) |ext| {
            if (mem.endsWith(u8, filename, ext)) {
                if (debug_mode) std.debug.print("Detected manga image with hash: {s} (ext: {s})\n", .{ filename, ext });
                return true;
            }
        }
    }

    for (extensions) |ext| {
        if (mem.endsWith(u8, filename, ext)) {
            if (debug_mode) std.debug.print("Detected image by extension: {s} (ext: {s})\n", .{ filename, ext });
            return true;
        }
    }

    const format_identifiers = [_][]const u8{ "png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp" };
    var lowercase_buf: [fs.max_path_bytes]u8 = undefined;
    var lowercase_filename: []u8 = undefined;
    if (filename.len < lowercase_buf.len) {
        for (filename, 0..) |char, i| {
            lowercase_buf[i] = std.ascii.toLower(char);
        }
        lowercase_filename = lowercase_buf[0..filename.len];
    } else {
        lowercase_filename = lowercase_buf[0..0]; // Handle potentially very long names gracefully
    }
    for (format_identifiers) |format| {
        if (std.mem.indexOf(u8, lowercase_filename, format) != null) {
            if (debug_mode) std.debug.print("Detected image by format identifier: {s} (format: {s})\n", .{ filename, format });
            return true;
        }
    }
    for (extensions) |ext| {
        const lowercase_ext = blk: {
            var ext_buf: [16]u8 = undefined;
            if (ext.len >= ext_buf.len) continue; // Prevent buffer overflow
            for (ext, 0..) |char, i| {
                ext_buf[i] = std.ascii.toLower(char);
            }
            break :blk ext_buf[0..ext.len];
        };
        if (lowercase_filename.len >= lowercase_ext.len) {
            const filename_end = lowercase_filename[lowercase_filename.len - lowercase_ext.len ..];
            if (mem.eql(u8, filename_end, lowercase_ext)) {
                if (debug_mode) std.debug.print("Detected image by case-insensitive extension: {s} (ext: {s})\n", .{ filename, ext });
                return true;
            }
        }
    }
    // if (debug_mode) std.debug.print("Not an image file: {s}\n", .{filename});
    return false;
}

pub fn countDirItems(dir_path: []const u8) !usize {
    var dir = try fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var count: usize = 0;
    var iter = dir.iterate();

    while (try iter.next()) |_| {
        count += 1;
    }

    return count;
}

pub fn isLargeDirectory(path: []const u8, threshold: usize) !bool {
    var dir = fs.cwd().openDir(path, .{ .iterate = true }) catch {
        return false;
    };
    defer dir.close();

    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |_| {
        count += 1;
        if (count > threshold) {
            return true;
        }
    }
    return false;
}

pub fn debug_print_directory_contents(path: []const u8, debug_mode: bool, threshold: usize) !void {
    if (!debug_mode) return;

    const directory_is_large = try isLargeDirectory(path, threshold);

    std.debug.print("Scanning directory: {s}\n", .{path});

    if (directory_is_large) {
        std.debug.print("Large directory detected (>{d} files). Skipping detailed debug output.\n", .{threshold});
        return;
    }

    // Use a platform-independent way to list directory contents if possible,
    // or handle different OS commands.
    // For simplicity, keeping `ls` for now, but this is not cross-platform.
    const argv = if (std.builtin.os.tag == .windows)
        &[_][]const u8{ "cmd", "/c", "dir", path }
    else
        &[_][]const u8{ "ls", "-la", path };

    const result = try process.Child.exec(.{
        .allocator = std.heap.page_allocator,
        .argv = argv,
        .max_output_bytes = 4096,
    });
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    std.debug.print("Directory contents:\n{s}\n", .{result.stdout});
    if (result.stderr.len > 0) {
        std.debug.print("Directory listing stderr:\n{s}\n", .{result.stderr});
    }
}
