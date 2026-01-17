const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const trade_module = b.addModule("trade", .{
        .root_source_file = b.path("src/trade.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = &trade_module; // suppress unused variable warning

    // Try the minimal test configuration
    const unit_tests = b.addTest(.{
        .root_module = trade_module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run unit tests").dependOn(&run_unit_tests.step);
}
