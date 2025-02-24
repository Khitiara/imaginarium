const std = @import("std");
const Build = std.Build;

const uacpi_src: []const []const u8 = &.{
    "tables.c",
    "types.c",
    "uacpi.c",
    "utilities.c",
    "interpreter.c",
    "opcodes.c",
    "namespace.c",
    "stdlib.c",
    "shareable.c",
    "opregion.c",
    "default_handlers.c",
    "io.c",
    "notify.c",
    "sleep.c",
    "registers.c",
    "resources.c",
    "event.c",
    "mutex.c",
    "osi.c",
};
const uacpi_flags: []const []const u8 = &.{
    "-ffreestanding",
    "-nostdlib",
    "-DUACPI_SIZED_FREES",
    // "-DUACPI_OVERRIDE_TYPES",
    "-DUACPI_OVERRIDE_ARCH_HELPERS",
    "-DUACPI_DEFAULT_LOG_LEVEL=UACPI_LOG_INFO",
};

pub fn add_uacpi_to_module(b: *Build, module: *Build.Module) void {
    const uacpi = b.dependency("uacpi", .{});
    module.addIncludePath(b.path("include"));
    module.addIncludePath(uacpi.path("include"));
    const headers = b.dependency("chdrs", .{});
    module.addIncludePath(headers.path("."));

    module.addCSourceFiles(.{
        .root = uacpi.path("source"),
        .files = uacpi_src,
        .flags = uacpi_flags,
    });
}

pub fn add_uacpi_to_build(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const uacpi = b.dependency("uacpi", .{});
    const copy = b.addUpdateSourceFiles();
    addTranslateAndCopy(b, "uacpi/kernel_api", uacpi, target, optimize, copy);
    addTranslateAndCopy(b, "uacpi/acpi", uacpi, target, optimize, copy);
    addTranslateAndCopy(b, "uacpi/uacpi", uacpi, target, optimize, copy);

    const translate = b.step("translate", "Translate UACPI headers");
    translate.dependOn(&copy.step);
}

fn addTranslateAndCopy(b: *std.Build, path: []const u8, uacpi: *std.Build.Dependency, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, copy: *std.Build.Step.UpdateSourceFiles) void {
    const t = b.addTranslateC(.{
        .link_libc = false,
        .target = target,
        .optimize = optimize,
        .root_source_file = uacpi.path(b.pathJoin(&.{ "include", b.fmt("{s}.h", .{path}) })),
    });
    t.addIncludePath(b.path("include"));
    t.addIncludePath(uacpi.path("include"));
    t.defineCMacro("UACPI_OVERRIDE_LIBC", null);
    t.defineCMacro("UACPI_SIZED_FREES", null);
    copy.addCopyFileToSource(t.getOutput(), b.pathJoin(&.{ "translate", b.fmt("{s}.zig", .{path}) }));
}