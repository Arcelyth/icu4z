const std = @import("std");

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    if (target.result.cpu.arch.endian() != .little)
        @panic("The bundled ICU data requires a little-endian target");

    const source = b.dependency("icu", .{});
    const module = b.createModule(.{
        .root_source_file = b.path("build/data.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .pic = true,
    });
    module.addCMacro("U_STATIC_IMPLEMENTATION", "1");
    module.addIncludePath(source.path("source/common"));
    module.addIncludePath(source.path("source/i18n"));

    addSources(b, module, source, "common", "U_COMMON_IMPLEMENTATION");
    addSources(b, module, source, "i18n", "U_I18N_IMPLEMENTATION");
    addData(b, module, source);
    linkPlatform(module, target);

    const library = b.addLibrary(.{
        .name = "icu",
        .linkage = .static,
        .root_module = module,
    });
    library.installHeadersDirectory(source.path("source/common/unicode"), "unicode", .{});
    library.installHeadersDirectory(source.path("source/i18n/unicode"), "unicode", .{});
    // copies ICU’s LICENSE
    const license = b.addInstallFile(source.path("LICENSE"), "share/licenses/icu/LICENSE");
    b.getInstallStep().dependOn(&license.step);
    return library;
}

// Uses ICU's source lists so updates do not need a second list of filenames.
fn addSources(
    b: *std.Build,
    module: *std.Build.Module,
    source: *std.Build.Dependency,
    directory: []const u8,
    implementation: []const u8,
) void {
    const contents = readFile(b, source, b.fmt("source/{s}/sources.txt", .{directory}));
    var files: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.tokenizeAny(u8, contents, " \t\r\n");
    while (lines.next()) |file|
        files.append(b.allocator, file) catch @panic("OOM");
    module.addCSourceFiles(.{
        .root = source.path(b.fmt("source/{s}", .{directory})),
        .files = files.items,
        .flags = &.{
            "-std=c++17",
            b.fmt("-D{s}=1", .{implementation}),
        },
    });
}

// Exports ICU's full data package under the name expected by its data loader.
fn addData(b: *std.Build, module: *std.Build.Module, source: *std.Build.Dependency) void {
    const major = majorVersion(b, source);
    const options = b.addOptions();
    options.addOption([]const u8, "symbol", b.fmt("icudt{d}_dat", .{major}));
    module.addOptions("data_options", options);
    module.addAnonymousImport("icudata", .{
        .root_source_file = source.path(b.fmt("source/data/in/icudt{d}l.dat", .{major})),
    });
}

fn majorVersion(b: *std.Build, source: *std.Build.Dependency) u32 {
    const header = readFile(b, source, "source/common/unicode/uvernum.h");
    const prefix = "#define U_ICU_VERSION_MAJOR_NUM ";
    var lines = std.mem.splitScalar(u8, header, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, prefix)) {
            const value = std.mem.trim(u8, line[prefix.len..], " \t\r");
            return std.fmt.parseInt(u32, value, 10) catch @panic("Invalid ICU version");
        }
    }
    @panic("ICU version is missing from uvernum.h");
}

fn readFile(b: *std.Build, source: *std.Build.Dependency, path: []const u8) []const u8 {
    b.dependOnFileContents(source.path(path));
    const file = source.builder.root.join(b.allocator, path) catch @panic("OOM");
    return file.root_dir.handle.readFileAlloc(b.graph.io, file.sub_path, b.allocator, .unlimited) catch |err|
        std.debug.panic("Cannot read ICU {s}: {s}", .{ path, @errorName(err) });
}

fn linkPlatform(module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    switch (target.result.os.tag) {
        .windows => module.linkSystemLibrary("advapi32", .{ .use_pkg_config = .no }),
        .linux => {
            module.linkSystemLibrary("pthread", .{ .use_pkg_config = .no });
            module.linkSystemLibrary("dl", .{ .use_pkg_config = .no });
            module.linkSystemLibrary("m", .{ .use_pkg_config = .no });
        },
        .macos => {},
        else => @panic("ICU4Z's bundled build supports macOS, Linux, and Windows"),
    }
}
