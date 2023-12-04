const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    var target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (target.isLinux() and !target.isGnuLibC()) {
        target.abi = .gnu;
    }

    const exe = b.addExecutable(.{
        .name = "remove-trash",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const pcre2 = b.dependency("pcre2", .{}).artifact("pcre2");
    exe.linkLibrary(pcre2);

    const clap = b.dependency("clap", .{}).module("clap");
    exe.addModule("clap", clap);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
