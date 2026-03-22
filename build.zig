// Noosphere Browser - Build Configuration
// This build.zig uses the standard Zig build system

const std = @import("std");
const CrossTarget = std.Build.CrossTarget;

pub fn build(b: *std.Build) void {
    // Get optimization setting from command line
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization level") orelse .ReleaseFast;

    // Target (defaults to native)
    const target = b.option(CrossTarget, "target", "Build target");

    // Create executable
    const exe = b.addExecutable(.{
        .name = "noosphere",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies
    exe.addModule("http", b.path("src/http.zig"));
    exe.addModule("parser", b.path("src/parser.zig"));
    exe.addModule("store", b.path("src/store.zig"));
    exe.addModule("ratelimit", b.path("src/ratelimit.zig"));
    exe.addModule("access", b.path("src/access.zig"));
    exe.addModule("p2p", b.path("src/p2p.zig"));
    exe.addModule("crypto", b.path("src/crypto.zig"));

    // Link system libraries
    exe.linkLibC();

    // Install
    b.installArtifact(exe);

    // Create test
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.addModule("http", b.path("src/http.zig"));
    tests.addModule("parser", b.path("src/parser.zig"));
    tests.addModule("store", b.path("src/store.zig"));

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunUnitTests(tests).step);

    // Build steps for common targets
    const build_x86 = b.step("build-x86", "Build for Linux x86_64");
    build_x86.dependOn(&addBuildStep(b, "x86_64-linux-gnu", optimize).step);

    const build_arm64 = b.step("build-arm64", "Build for Linux ARM64");
    build_arm64.dependOn(&addBuildStep(b, "aarch64-linux-gnu", optimize).step);

    const build_pi = b.step("build-pi", "Build for Raspberry Pi (ARM64)");
    build_pi.dependOn(&addBuildStep(b, "aarch64-linux-gnu", optimize).step);

    // Default step
    const default_step = b.step("build", "Build for current platform");
    default_step.dependOn(&b.addInstallArtifactStep(exe).step);
}

fn addBuildStep(b: *std.Build, target_str: []const u8, optimize: std.builtin.OptimizeMode) *std.Build.Step {
    const target = std.Build.CrossTarget.parse(target_str) catch @panic("Invalid target");
    
    const exe = b.addExecutable(.{
        .name = "noosphere",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("http", b.path("src/http.zig"));
    exe.addModule("parser", b.path("src/parser.zig"));
    exe.addModule("store", b.path("src/store.zig"));
    exe.addModule("ratelimit", b.path("src/ratelimit.zig"));
    exe.addModule("access", b.path("src/access.zig"));
    exe.addModule("p2p", b.path("src/p2p.zig"));
    exe.addModule("crypto", b.path("src/crypto.zig"));

    exe.linkLibC();

    return &b.addInstallArtifactStep(exe).step;
}
