const std = @import("std");
const fs = std.fs;
const process = std.process;
const mem = std.mem;
const State = @import("state.zig").State;
const sdl = @import("sdl_utils.zig"); // Needed for loadCurrentImage

// Define potential errors for the upscaler
pub const UpscalerError = error{
    UpscalingTimeout,
    UpscalingFailed,
    OutputPathGenerationFailed,
    ProcessSpawnFailed,
    ProcessWaitFailed,
    StdErrReadFailed,
    OutputFileMissing,
    PathDuplicationFailed,
    StateUpdateFailed,
};

pub fn upscaleCurrentImage(state: *State, scale: u8) !void {
    if (state.image_paths.items.len == 0) {
        return; // Nothing to upscale
    }

    const input_path = state.image_paths.items[state.current_image];
    var output_path_buf: [fs.max_path_bytes]u8 = undefined;
    var output_path: []u8 = undefined;

    // Generate output path
    const last_dot = std.mem.lastIndexOf(u8, input_path, ".");
    if (last_dot != null) {
        const base = input_path[0..last_dot.?];
        const ext = input_path[last_dot.?..];
        output_path = std.fmt.bufPrint(&output_path_buf, "{s}_upscaledx{d}{s}", .{ base, scale, ext }) catch |err| {
            std.debug.print("Error formatting output path: {any}\n", .{err});
            return UpscalerError.OutputPathGenerationFailed;
        };
    } else {
        output_path = std.fmt.bufPrint(&output_path_buf, "{s}_upscaledx{d}", .{ input_path, scale }) catch |err| {
            std.debug.print("Error formatting output path (no ext): {any}\n", .{err});
            return UpscalerError.OutputPathGenerationFailed;
        };
    }

    std.debug.print("Upscaling image: {s} -> {s} (scale: {d})\n", .{ input_path, output_path, scale });

    // --- Upscaler Script and Environment Logic ---
    var script_path: []const u8 = "upscale/main.py"; // Default relative path
    var upscale_dir: []const u8 = "upscale";
    var install_dir_script_exists = false;

    // Check potential installation paths
    const install_paths = [_][]const u8{
        "/usr/local/share/zimg/upscale/main.py",
        "/usr/share/zimg/upscale/main.py",
    };
    for (install_paths) |p| {
        if (fs.cwd().access(p, .{})) {
            script_path = p;
            upscale_dir = std.fs.path.dirname(p) orelse upscale_dir;
            install_dir_script_exists = true;
            std.debug.print("Found upscaler script at installed path: {s}\n", .{script_path});
            break;
        } else |_| {}
    }

    var use_venv = false;
    var venv_path: []const u8 = "";
    var venv_candidates_storage: [4]?[]const u8 = [_]?[]const u8{null} ** 4;
    var allocated_venv_paths = std.ArrayList([]u8).init(state.allocator); // Track allocated paths
    defer {
        for (allocated_venv_paths.items) |p| state.allocator.free(p);
        allocated_venv_paths.deinit();
    }

    if (install_dir_script_exists) {
        venv_candidates_storage[0] = try std.fmt.allocPrint(state.allocator, "{s}/venv", .{upscale_dir});
        try allocated_venv_paths.append(venv_candidates_storage[0].?); // Track for freeing
        venv_candidates_storage[1] = try std.fmt.allocPrint(state.allocator, "{s}/.venv", .{upscale_dir});
        try allocated_venv_paths.append(venv_candidates_storage[1].?);
        venv_candidates_storage[2] = "venv"; // Relative check
        venv_candidates_storage[3] = ".venv"; // Relative check
    } else {
        venv_candidates_storage[0] = "upscale/venv";
        venv_candidates_storage[1] = "upscale/.venv";
        venv_candidates_storage[2] = "venv";
        venv_candidates_storage[3] = ".venv";
    }

    for (venv_candidates_storage) |maybe_candidate| {
        if (maybe_candidate) |candidate| {
            if (fs.cwd().access(candidate, .{})) {
                use_venv = true;
                venv_path = candidate;
                std.debug.print("Found virtual environment at: {s}\n", .{venv_path});
                break;
            } else |_| {}
        }
    }

    // --- Process Execution Logic ---
    var argv = std.ArrayList([]const u8).init(state.allocator);
    defer argv.deinit();
    var allocated_argv_items = std.ArrayList([]u8).init(state.allocator);
    defer {
        for (allocated_argv_items.items) |item| state.allocator.free(item);
        allocated_argv_items.deinit();
    }

    // Build the command arguments
    if (use_venv) {
        const builtin = @import("builtin");
        if (builtin.os.tag == .windows) {
            try argv.appendSlice(&[_][]const u8{ "cmd.exe", "/c" });
            const activate_path = try std.fmt.allocPrint(state.allocator, "{s}\\Scripts\\activate.bat && python {s} \"{s}\" \"{s}\" --scale {d}", .{ venv_path, script_path, input_path, output_path, scale });
            try allocated_argv_items.append(activate_path);
            try argv.append(activate_path);
        } else {
            try argv.appendSlice(&[_][]const u8{ "sh", "-c" });
            const activate_cmd = try std.fmt.allocPrint(state.allocator, "timeout 300 bash -c 'source {s}/bin/activate && python {s} \"{s}\" \"{s}\" --scale {d}' || echo 'Upscaling process timed out or failed'", .{ venv_path, script_path, input_path, output_path, scale });
            try allocated_argv_items.append(activate_cmd);
            try argv.append(activate_cmd);
        }
    } else {
        try argv.append("python3");
        try argv.append(script_path);
        try argv.append(input_path);
        try argv.append(output_path);
        try argv.append("--scale");
        const scale_str = try std.fmt.allocPrint(state.allocator, "{d}", .{scale});
        try allocated_argv_items.append(scale_str);
        try argv.append(scale_str);
    }

    // Spawn and manage the process
    var child = std.process.Child.init(argv.items, state.allocator);
    child.stdin_behavior = .Close;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    child.spawn() catch |err| {
        std.debug.print("Failed to spawn upscaling process: {any}\n", .{err});
        // Attempt fallback to 'python' if 'python3' failed and not using venv
        if (!use_venv and std.mem.eql(u8, argv.items[0], "python3")) {
            std.debug.print("Retrying with 'python'...\n", .{});
            argv.items[0] = "python";
            child = std.process.Child.init(argv.items, state.allocator);
            // Re-init stdio pipes
            child.stdin_behavior = .Close;
            child.stdout_behavior = .Pipe;
            child.stderr_behavior = .Pipe;
            child.spawn() catch |retry_err| {
                std.debug.print("Failed to spawn upscaling process with 'python': {any}\n", .{retry_err});
                return UpscalerError.ProcessSpawnFailed;
            };
        } else {
            return UpscalerError.ProcessSpawnFailed;
        }
    };

    // Wait for process with timeout
    const start_time = std.time.milliTimestamp();
    const timeout_ms: i64 = 300000; // 5 minutes

    const result = child.wait() catch |err| {
        std.debug.print("Error waiting for upscaling process: {any}\n", .{err});
        return UpscalerError.ProcessWaitFailed;
    };

    const elapsed_time = std.time.milliTimestamp() - start_time;
    if (elapsed_time >= timeout_ms) {
        std.debug.print("Upscaling process timed out after {d} ms\n", .{elapsed_time});
        _ = child.kill() catch {}; // Attempt to kill
        return UpscalerError.UpscalingTimeout;
    }

    // Check process result and output
    const stdout = child.stdout.?.reader().readAllAlloc(state.allocator, 1024) catch "";
    defer state.allocator.free(stdout);
    std.debug.print("Upscaler stdout: {s}", .{stdout});

    if (result.Exited != 0 or std.mem.contains(u8, stdout, "failed")) {
        const stderr = child.stderr.?.reader().readAllAlloc(state.allocator, 10 * 1024) catch |e| {
            std.debug.print("Could not read stderr after failed upscale: {any}\n", .{e});
            return UpscalerError.StdErrReadFailed;
        };
        defer state.allocator.free(stderr);
        std.debug.print("Python upscaler error (exit code {d}): {s}\n", .{ result.Exited, stderr });
        return UpscalerError.UpscalingFailed;
    }

    // Verify output file exists
    fs.cwd().access(output_path, .{}) catch {
        std.debug.print("Upscaling failed: output file {s} not found\n", .{output_path});
        return UpscalerError.OutputFileMissing;
    };

    // Update state: Add new path and reload image
    const owned_output_path = state.allocator.dupe(u8, output_path) catch |err| {
        std.debug.print("Failed to duplicate output path string: {any}\n", .{err});
        return UpscalerError.PathDuplicationFailed;
    };
    state.image_paths.append(owned_output_path) catch |err| {
        std.debug.print("Failed to append upscaled path to list: {any}\n", .{err});
        state.allocator.free(owned_output_path); // Clean up duplicated path if append fails
        return UpscalerError.StateUpdateFailed;
    };

    state.current_image = state.image_paths.items.len - 1;
    try sdl.loadCurrentImage(state);

    std.debug.print("Upscaling complete!\n", .{});
}
