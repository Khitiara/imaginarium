const std = @import("std");
const Build = std.Build;
const Target = std.Target;
const LazyPath = Build.LazyPath;
const utils = @import("util.zig");

fn re_query(arch: Target.Cpu.Arch) !Target.Query {
    var query: Target.Query = .{
        .abi = .none,
        .os_tag = .freestanding,
    };
    query.cpu_model = .{ .explicit = std.Target.Cpu.Model.generic(arch) };
    switch (arch) {
        .x86_64 => {
            query.cpu_arch = .x86;
            const Features = std.Target.x86.Feature;
            // zig needs floats of some sort, but we dont want to use simd in kernel
            query.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));
            query.cpu_features_add.addFeature(@intFromEnum(Features.rdrnd));
            query.cpu_features_add.addFeature(@intFromEnum(Features.rdseed));

            query.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
            query.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));
        },
        .aarch64 => return error.no_stage2_for_aarch64,
        else => return error.invalid_imaginarium_arch,
    }
    return query;
}

pub fn add_stage2(b: *Build, arch: Target.Cpu.Arch, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !struct {
    *std.Build.Step.Compile,
    *std.Build.Step,
    LazyPath,
    ?LazyPath,
} {
    const exe_name = "imaginarium.ldr.b";
    const exe = b.addExecutable(.{
        .name = "stage2.elf",
        .root_source_file = b.path("src/ldr/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .pic = false,
        .use_llvm = true,
        .use_lld = true,
        .strip = false,
        // .single_threaded = true,
        .omit_frame_pointer = false,
        .zig_lib_dir = b.path("zig-std/lib"),
    });

    exe.build_id = .uuid;
    exe.pie = false;
    exe.entry = .disabled;

    const exe_module = exe.root_module;
    utils.addImportFromTable(exe_module, "util");
    utils.addImportFromTable(exe_module, "config");
    utils.addImportFromTable(exe_module, "cmn");

    const zuacpi = b.dependency("zuacpi", .{ .log_level = .info, .override_arch_helpers = true });

    const zuacpi_module = zuacpi.module("zuacpi_barebones");
    zuacpi_module.addIncludePath(b.path("include"));
    const headers = b.dependency("chdrs", .{});
    zuacpi_module.addIncludePath(headers.path("."));

    exe_module.addImport("zuacpi", zuacpi_module);

    exe.setLinkerScript(b.path("src/ldr/link.ld"));

    const ldrstep = b.step("ldr", "imaginarium stage2 bootloader");
    ldrstep.dependOn(&b.addInstallArtifact(exe, .{
        .dest_dir = .{
            .override = .{
                .custom = "agony",
            },
        },
    }).step);
    const objcopy = b.addObjCopy(exe.getEmittedBin(), .{
        .strip = .debug_and_symbols,
        .basename = exe_name,
        .extract_to_separate_file = true,
    });

    const ldroutdir = b.fmt("{s}/ldr/", .{@tagName(arch)});
    utils.installFrom(b, &objcopy.step, ldrstep, objcopy.getOutput(), ldroutdir, b.dupe(exe_name));
    // installFrom(b, &exe.step, ldrstep, ir, "agony", "something.ir");
    if (objcopy.getOutputSeparatedDebug()) |dbg| {
        utils.installFrom(b, &objcopy.step, ldrstep, dbg, ldroutdir, try std.mem.concat(b.allocator, u8, &.{ exe_name, ".debug" }));
    }

    b.getInstallStep().dependOn(ldrstep);

    return .{
        exe,
        ldrstep,
        objcopy.getOutput(),
        objcopy.getOutputSeparatedDebug(),
    };
}
