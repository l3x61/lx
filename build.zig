const std = @import("std");
const zon = @import("build.zig.zon");

const name = @tagName(zon.name);
const version = zon.version;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const options = b.addOptions();
    options.addOption([]const u8, "name", name);
    options.addOption([]const u8, "version", version);
    exe_mod.addOptions("build_options", options);

    const exe = b.addExecutable(.{ .name = name, .root_module = exe_mod });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run executable");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");
    const tests = b.addTest(.{ .root_module = exe_mod });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    const spec_mod = b.createModule(.{
        .root_source_file = b.path("spec/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    const src_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    spec_mod.addImport("src", src_mod);
    const spec_exe = b.addExecutable(.{ .name = "spec", .root_module = spec_mod });
    const spec_cmd = b.addRunArtifact(spec_exe);
    const spec_step = b.step("spec", "Run spec files in spec/pass and spec/fail");
    spec_step.dependOn(&spec_cmd.step);
}
