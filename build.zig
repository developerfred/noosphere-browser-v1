// Noosphere Browser - Build Configuration
// Supports: Linux (x86_64, ARM64, ARMv7), macOS (Intel, Apple Silicon), Windows

const std = @import("std");
const CrossTarget = std.Build.CrossTarget;

pub fn build(b: *std.Build) void {
    // Main binary
    const exe = b.addExecutable(.{
        .name = "noosphere",
        .root_source_file = b.path("src/main.zig"),
        .target = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
        },
        .optimize = .ReleaseFast,
    });

    // Add source files
    exe.addModule("http", b.path("src/http.zig"));
    exe.addModule("parser", b.path("src/parser.zig"));
    exe.addModule("store", b.path("src/store.zig"));

    // Install
    b.installArtifact(exe);

    // Standard options
    const target_option = b.option(std.Build.CrossTarget, "target", "Build target (e.g., x86_64-linux-gnu, aarch64-linux-gnu)");
    const fd = b.option(bool, "fd", "Enable fd tracing", false);

    _ = target_option;
    _ = fd;
}

// Multi-platform build helper
pub fn buildAllTargets(b: *std.Build) void {
    const targets = .{
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .gnueabihf },
        .{ .cpu_arch = .x86_64, .os_tag = .macos, .abi = null },
        .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = null },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    };

    inline for (targets) |target| {
        const cross_target = CrossTarget{
            .cpu_arch = target.cpu_arch,
            .os_tag = target.os_tag,
            .abi = target.abi,
        };

        var exe = b.addExecutable(.{
            .name = "noosphere",
            .root_source_file = b.path("src/main.zig"),
            .target = cross_target,
            .optimize = .ReleaseFast,
        });

        exe.addModule("http", b.path("src/http.zig"));
        exe.addModule("parser", b.path("src/parser.zig"));
        exe.addModule("store", b.path("src/store.zig"));

        const output_path = b.path(std.fmt.comptimePrint("zig-out/bin/noosphere-{s}-{s}", .{
            @tagName(target.cpu_arch),
            @tagName(target.os_tag),
        }));

        b.installArtifactAtPath(exe, output_path);
    }
}
