const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shell = b.addExecutable(.{
        .name = "brick-shell",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(shell);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
            .link_libc = true,
        }),
    });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const simulator = b.addExecutable(.{
        .name = "brick-ui-simulator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/simulator.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .link_libc = true,
        }),
    });
    const simulator_step = b.step("simulator", "Build the desktop simulator");
    simulator_step.dependOn(&b.addInstallArtifact(simulator, .{}).step);
}
