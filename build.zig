const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const library = @import("build/icu.zig").build(b, target, optimize);
    // Provide build output.
    b.installArtifact(library);

    const t: Translator = .init(b.dependency("translate_c", .{}), .{
        .c_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    t.defineCMacro("U_STATIC_IMPLEMENTATION", "1");
    t.defineCMacro("U_DISABLE_RENAMING", "1");
    t.linkLibrary(library);

    const module = b.addModule("icu4z", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "c", .module = t.mod }},
    });

    // Test step.
    const test_step = b.step("test", "Run all tests");

    const unit_tests = b.addTest(.{
        .name = "tests",
        .root_module = module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}
