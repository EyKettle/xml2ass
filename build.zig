const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    const native_target = b.standardTargetOptions(.{});

    const native_exe = b.addExecutable(.{
        .name = "xml2ass",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = native_target,
            .optimize = optimize,
            .strip = optimize != .Debug,
        }),
    });
    native_exe.lto = if (optimize == .Debug and native_target.result.os.tag == .linux) .none else .full;

    b.installArtifact(native_exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(native_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");

    const exe_test = b.addTest(.{
        .root_module = native_exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_test);
    test_step.dependOn(&run_exe_tests.step);

    const make_all_step = b.step("all", "Make all binaries");
    const targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    };

    for (targets) |target| {
        const resolved_target = b.resolveTargetQuery(target);
        const exe = b.addExecutable(.{
            .name = "xml2ass",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = resolved_target,
                .optimize = optimize,
                .strip = true,
            }),
        });
        exe.lto = if (optimize != .Debug and resolved_target.result.os.tag == .linux) .full else .none;

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try target.zigTriple(b.allocator),
                },
            },
        });
        make_all_step.dependOn(&target_output.step);
    }
}
