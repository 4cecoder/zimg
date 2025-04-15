const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;

pub const Config = struct {
    max_files: usize = 10000,
    max_images: usize = 5000,
    max_subdirs: usize = 100,
    max_depth: usize = 5,
    debug_mode: bool = false,
    suggestion_threshold: usize = 3,
    batch_size: usize = 100,
};

pub fn loadConfig(allocator: Allocator) Config {
    // Default config
    var config = Config{};

    // Possible config file locations
    const config_locations = [_][]const u8{
        "config.toml",
        "/usr/local/share/zimg/config.toml",
        "/usr/share/zimg/config.toml",
    };

    var config_file_path: ?[]const u8 = null;
    var file_content: []u8 = undefined;
    var file_found = false;

    // Try to find and read the config file
    for (config_locations) |path| {
        if (std.fs.cwd().openFile(path, .{})) |file| {
            defer file.close();
            file_content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
                std.debug.print("Error reading config file '{s}': {any}\n", .{ path, err });
                continue;
            };
            config_file_path = path;
            file_found = true;
            break;
        } else |_| {
            continue;
        }
    }

    if (!file_found) {
        std.debug.print("Config file not found in any location. Using default settings.\n", .{});
        return config;
    }

    defer if (file_found) allocator.free(file_content);

    // Basic parsing of TOML-like file for specific keys
    std.debug.print("Loading configuration from '{s}'...\n", .{config_file_path.?});
    var lines = std.mem.splitSequence(u8, file_content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.indexOf(u8, trimmed, "=")) |eq_index| {
            const key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
            const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
            const value_end = if (std.mem.indexOf(u8, value, "#")) |comment| std.mem.trim(u8, value[0..comment], " \t") else value;

            if (std.mem.eql(u8, key, "max_files")) {
                config.max_files = std.fmt.parseInt(usize, value_end, 10) catch config.max_files;
            } else if (std.mem.eql(u8, key, "max_images")) {
                config.max_images = std.fmt.parseInt(usize, value_end, 10) catch config.max_images;
            } else if (std.mem.eql(u8, key, "max_subdirs")) {
                config.max_subdirs = std.fmt.parseInt(usize, value_end, 10) catch config.max_subdirs;
            } else if (std.mem.eql(u8, key, "max_depth")) {
                config.max_depth = std.fmt.parseInt(usize, value_end, 10) catch config.max_depth;
            } else if (std.mem.eql(u8, key, "debug_mode")) {
                config.debug_mode = if (std.mem.eql(u8, value_end, "true")) true else false;
            } else if (std.mem.eql(u8, key, "suggestion_threshold")) {
                config.suggestion_threshold = std.fmt.parseInt(usize, value_end, 10) catch config.suggestion_threshold;
            } else if (std.mem.eql(u8, key, "batch_size")) {
                config.batch_size = std.fmt.parseInt(usize, value_end, 10) catch config.batch_size;
            }
        }
    }

    std.debug.print("Configuration loaded successfully: max_depth={d}, debug_mode={any}\n", .{ config.max_depth, config.debug_mode });
    return config;
} 