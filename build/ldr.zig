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

pub fn add_stage2(b: *Build, arch: Target.Cpu.Arch, optimize: std.builtin.OptimizeMode)  !struct {
    *std.Build.Step.Compile,
    *std.Build.Step,
    LazyPath,
    ?LazyPath,
} {
    const query = try re_query(arch);
    const stage2_target = b.resolveTargetQuery(query);

    const exe_name = "imaginarium.ldr.b";
    const exe = b.addExecutable(.{
        .name = "stage2.elf",
        .root_source_file = b.path("src/ldr/main.zig"),
        .target = stage2_target,
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

    exe.addAssemblyFile(b.path("src/ldr/init.S"));
    exe.addAssemblyFile(b.path("src/ldr/real.S"));

    const exe_module = &exe.root_module;
    utils.addImportFromTable(exe_module, "util");
    utils.addImportFromTable(exe_module, "config");
    utils.addImportFromTable(exe_module, "cmn");

    exe.setLinkerScript(b.path("src/ldr/link.ld"));

    const krnlstep = b.step("ldr", "imaginarium stage2 bootloader");
    krnlstep.dependOn(&b.addInstallArtifact(exe, .{
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

    const krnloutdir = b.fmt("{s}/ldr/", .{@tagName(arch)});
    utils.installFrom(b, &objcopy.step, krnlstep, objcopy.getOutput(), krnloutdir, b.dupe(exe_name));
    // installFrom(b, &exe.step, krnlstep, ir, "agony", "something.ir");
    if (objcopy.getOutputSeparatedDebug()) |dbg| {
        utils.installFrom(b, &objcopy.step, krnlstep, dbg, krnloutdir, try std.mem.concat(b.allocator, u8, &.{ exe_name, ".debug" }));
    }

    b.getInstallStep().dependOn(krnlstep);

    return .{
        exe,
        krnlstep,
        objcopy.getOutput(),
        objcopy.getOutputSeparatedDebug(),
    };
}