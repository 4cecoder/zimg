const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zimg",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Link SDL2 and SDL2_image
    // This assumes SDL2 and SDL2_image development libraries are installed system-wide
    // or discoverable via pkg-config.
    // You might need to adjust linking based on your system setup.
    // For Windows/macOS, you might need to specify library paths explicitly.
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_image");

    // On macOS, you might need to link frameworks
    if (target.isDarwin()) {
        exe.linkFramework("SDL2");
        exe.linkFramework("SDL2_image");
        // Add other frameworks if needed by SDL or its dependencies
        exe.linkFramework("Cocoa"); // Often needed for windowing
        exe.linkFramework("OpenGL"); // If using OpenGL renderer backend
    }

    // Link C libraries
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
