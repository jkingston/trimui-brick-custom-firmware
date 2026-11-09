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

    // Explicit experiment only: never part of the production shell build.
    const gpu_module = b.createModule(.{
        .root_source_file = b.path("tools/gpu-dmabuf-probe.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    gpu_module.addImport("pango", b.createModule(.{
        .root_source_file = b.path("src/text_pango.zig"),
        .target = target,
        .optimize = optimize,
    }));
    gpu_module.addLibraryPath(b.path("output/build/build/brick-gpu-1.1.1-20251126/runtime/usr/lib"));
    gpu_module.addLibraryPath(b.path("output/build/staging/usr/lib"));
    gpu_module.linkSystemLibrary("EGL", .{ .use_pkg_config = .no });
    gpu_module.linkSystemLibrary("GLESv2", .{ .use_pkg_config = .no });
    gpu_module.linkSystemLibrary("drm", .{ .use_pkg_config = .no });
    const gpu = b.addExecutable(.{ .name = "brick-gpu-spike", .root_module = gpu_module });
    gpu.linker_allow_shlib_undefined = true;
    const gpu_step = b.step("gpu-spike", "Build the opt-in vendor GLES/DMA-BUF/KMS spike");
    gpu_step.dependOn(&b.addInstallArtifact(gpu, .{}).step);

    const plane_probe_module = b.createModule(.{
        .root_source_file = b.path("tools/kms-plane-probe.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    plane_probe_module.addLibraryPath(b.path("output/build/staging/usr/lib"));
    plane_probe_module.linkSystemLibrary("drm", .{ .use_pkg_config = .no });
    const plane_probe = b.addExecutable(.{ .name = "kms-plane-probe", .root_module = plane_probe_module });
    plane_probe.linker_allow_shlib_undefined = true;
    const plane_probe_step = b.step("kms-plane-probe", "Build the KMS plane inventory and atomic test probe");
    plane_probe_step.dependOn(&b.addInstallArtifact(plane_probe, .{}).step);

    const tearing_repros = b.step("tearing-repros", "Build the complete on-device tearing reproduction suite");
    tearing_repros.dependOn(&b.addInstallArtifact(gpu, .{}).step);
    tearing_repros.dependOn(&b.addInstallArtifact(plane_probe, .{}).step);
    tearing_repros.dependOn(&b.addInstallBinFile(b.path("tools/run-tearing-repros"), "run-tearing-repros").step);
}
