const std = @import("std");
const Target = std.Target;
const Build = std.Build;
const LazyPath = Build.LazyPath;

const uacpi = @import("uacpi.zig");
const utils = @import("util.zig");

pub fn add_krnl(b: *Build, arch: Target.Cpu.Arch, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !struct {
    *std.Build.Step.Compile,
    *std.Build.Step,
    LazyPath,
    ?LazyPath,
} {
    const exe_name = "imaginarium.krnl.b";

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/krnl/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .pic = false,
        .strip = false,
        .omit_frame_pointer = false,
        .error_tracing = true,
        // .single_threaded = true,
        // .red_zone = false;
        // .dwarf_format = .@"64";
    });

    exe_module.addAssemblyFile(b.path("src/krnl/hal/arch/ap_trampoline.S"));
    exe_module.addAssemblyFile(b.path("src/krnl/hal/arch/kstart.S"));

    uacpi.add_uacpi_to_module(b, exe_module);

    utils.addImportFromTable(exe_module, "util");
    utils.addImportFromTable(exe_module, "config");
    utils.addImportFromTable(exe_module, "zuid");
    utils.addImportFromTable(exe_module, "cmn");
    utils.addImportFromTable(exe_module, "collections");

    const exe = b.addExecutable(.{
        .name = "imaginarium.elf",
        .root_module = exe_module,
        .use_llvm = true,
        .use_lld = true,
        .zig_lib_dir = b.path("zig-std/lib"),
    });
    exe.build_id = .uuid;
    exe.pie = false;
    exe.entry = .disabled;

    exe.setLinkerScript(b.path("src/krnl/link.ld"));

    const krnlstep = b.step("krnl", "imaginarium kernel");
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

    const krnloutdir = b.fmt("{s}/krnl/", .{@tagName(arch)});
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
