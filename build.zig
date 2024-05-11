const std = @import("std");
const log = std.log;
const Target = std.Target;
const DiskImage = @import("build/disk_image.zig");
const LazyPath = std.Build.LazyPath;

fn target_features(query: *Target.Query) !void {
    query.cpu_model = .{ .explicit = std.Target.Cpu.Model.generic(query.cpu_arch.?) };
    switch (query.cpu_arch.?) {
        .x86_64 => {
            const Features = std.Target.x86.Feature;
            // zig needs floats of some sort, but we dont want to use simd in kernel
            query.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

            query.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
            query.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
            query.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));
        },
        .aarch64 => {
            // for now nothing, idk what needs tweaking here
        },
        else => return error.invalid_imaginarium_arch,
    }
}

fn installFrom(b: *std.Build, dep: *std.Build.Step, group_step: *std.Build.Step, file: LazyPath, dir: []const u8, rel: []const u8) void {
    const s = b.addInstallFileWithDir(file, .{ .custom = dir }, rel);
    s.step.dependOn(dep);
    group_step.dependOn(&s.step);
}

fn addImportFromTable(module: *std.Build.Module, name: []const u8) void {
    if (module.owner.modules.get(name)) |d| {
        module.addImport(name, d);
    }
}

fn krnl(b: *std.Build, arch: Target.Cpu.Arch, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !struct {
    *std.Build.Step,
    LazyPath,
    ?LazyPath,
} {
    const hal = b.createModule(.{
        .root_source_file = b.path("src/hal/hal.zig"),
    });
    addImportFromTable(hal, "config");
    addImportFromTable(hal, "util");
    addImportFromTable(hal, "zuid");

    const exe_name = "imaginarium.krnl.b";
    const exe = b.addExecutable(.{
        .name = "imaginarium.elf",
        .root_source_file = b.path("src/krnl/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
        .pic = false,
        .use_lld = true,
        .strip = false,
        .single_threaded = true,
    });
    b.verbose_llvm_ir = "agony.ir";
    b.verbose_llvm_bc = "agony.bc";
    const ir = exe.getEmittedLlvmIr();
    // exe.export_memory = true;
    exe.entry = .disabled;

    const exe_module = &exe.root_module;
    // exe_module.dwarf_format = .@"64";
    exe_module.addImport("hal", hal);

    exe.addAssemblyFile(b.path(b.fmt("src/hal/arch/{s}/ap_trampoline.S", .{@tagName(arch)})));

    addImportFromTable(exe_module, "util");
    addImportFromTable(exe_module, "config");
    addImportFromTable(exe_module, "zuid");

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
    installFrom(b, &objcopy.step, krnlstep, objcopy.getOutput(), krnloutdir, b.dupe(exe_name));
    installFrom(b, &exe.step, krnlstep, ir, "agony", "something.ir");
    if (objcopy.getOutputSeparatedDebug()) |dbg| {
        installFrom(b, &objcopy.step, krnlstep, dbg, krnloutdir, try std.mem.concat(b.allocator, u8, &.{ exe_name, ".debug" }));
    }

    b.getInstallStep().dependOn(krnlstep);

    return .{
        krnlstep,
        objcopy.getOutput(),
        objcopy.getOutputSeparatedDebug(),
    };
}

fn usr(b: *std.Build, arch: Target.Cpu.Arch, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    // const lib_name = switch (arch) {
    //     inline else => |a| "imaginarium." ++ @tagName(a) ++ ".usr.l",
    // };
    const lib_name = "imaginarium.usr.l";
    // defer b.allocator.free(lib_name);
    const dynlib_name = "imaginarium.usr.dyn";
    // defer b.allocator.free(dynlib_name);

    const usrlib = b.addStaticLibrary(.{
        .name = lib_name,
        .root_source_file = b.path("src/usr/usr_lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    usrlib.out_lib_filename = b.dupe(usrlib.name);

    // cant create from existing module so invert that and create the object first
    const usr_imports = b.addObject(.{
        .name = dynlib_name,
        .root_source_file = b.path("src/usr/usr_lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    addImportFromTable(&usr_imports.root_module, "util");
    addImportFromTable(&usr_imports.root_module, "config");

    // cant create an object compile step from an existing module so get the root module of the object step
    // and add that manually to the modules map
    b.modules.put("usr", &usr_imports.root_module) catch @panic("OOM");

    const usrstep = b.step("usr", "usermode kernel services");

    const usroutdir = b.fmt("{s}/usr", .{@tagName(arch)});
    // defer b.allocator.free(usroutdir);

    usrstep.dependOn(&b.addInstallArtifact(usrlib, .{
        .dest_dir = .{ .override = .{ .custom = usroutdir } },
    }).step);
    usrstep.dependOn(&b.addInstallFile(b.path("src/usr/usr.zig"), try std.mem.concat(b.allocator, u8, &.{ usroutdir, "/include/usr.zig" })).step);
    usrstep.dependOn(&b.addInstallFile(b.path("src/usr/usr.h"), try std.mem.concat(b.allocator, u8, &.{ usroutdir, "/include/usr.h" })).step);
    usrstep.dependOn(&usr_imports.step);

    b.getInstallStep().dependOn(usrstep);
}

const QemuGdbOption = union(enum) {
    none: void,
    default: void,
    port: u32,
};

fn parseQemuGdbOption(v: ?[]const u8) QemuGdbOption {
    if (v) |value| {
        if (std.mem.eql(u8, value, "none")) {
            return .none;
        }
        if (value.len == 0 or std.mem.eql(u8, value, "default")) {
            return .default;
        }
        if (std.fmt.parseInt(u32, value, 0)) |i| {
            return .{ .port = i };
        } else |_| {}
        @panic("Invalid qemu gdb option");
    } else {
        return .none;
    }
}

const bootelf = @import("bootelf");
fn img(b: *std.Build, arch: Target.Cpu.Arch, krnlstep: *std.Build.Step, elf: LazyPath, symbols: ?LazyPath) !struct { *std.Build.Step, LazyPath } {
    const ldr_img = try bootelf.make_bootelf(b);
    const disk_image = DiskImage.create(b, .{
        .basename = "drive.bin",
    });
    disk_image.append(ldr_img);
    disk_image.append(elf);
    disk_image.step.dependOn(krnlstep);

    b.getInstallStep().dependOn(&disk_image.step);

    const step = b.step("img", "create bootable disk image for the target");
    installFrom(b, &disk_image.step, step, disk_image.getOutput(), b.fmt("{s}/img", .{@tagName(arch)}), disk_image.basename);

    const copyToTestDir = b.addNamedWriteFiles("copy_to_test_dir");
    copyToTestDir.step.dependOn(&disk_image.step);
    copyToTestDir.step.dependOn(krnlstep);
    copyToTestDir.addCopyFileToSource(disk_image.getOutput(), "test/drive.bin");
    if (symbols) |d| {
        copyToTestDir.addCopyFileToSource(d, "test/krnl.debug");
    }
    step.dependOn(&copyToTestDir.step);
    return .{ step, disk_image.getOutput() };
}

pub fn build(b: *std.Build) !void {
    const arch = b.option(Target.Cpu.Arch, "arch", "The CPU architecture to build for") orelse .x86_64;
    var selected_target: Target.Query = .{
        .abi = .none,
        .os_tag = .freestanding,
        .cpu_arch = arch,
    };
    try target_features(&selected_target);
    const target = b.resolveTargetQuery(selected_target);
    const optimize = b.standardOptimizeOption(.{});

    const max_ioapics = b.option(u32, "max_ioapics", "maximum number of ioapics supported (default 5)") orelse 5;

    const options = b.addOptions();
    options.addOption(u32, "max_ioapics", max_ioapics);
    options.addOption(bool, "rsdp_search_bios", true);

    const optsModule = options.createModule();
    b.modules.put("config", optsModule) catch @panic("OOM");

    const zuid_dep = b.dependency("zuid", .{});
    b.modules.put("zuid", zuid_dep.module("zuid")) catch @panic("OOM");

    const util = b.addModule("util", .{
        .root_source_file = b.path("src/util/util.zig"),
    });
    addImportFromTable(util, "config");
    addImportFromTable(util, "zuid");

    const krnlstep, const elf, const debug = try krnl(b, arch, target, optimize);
    const imgstep, const imgFile = try img(b, arch, krnlstep, elf, debug);

    const qemu = b.addSystemCommand(&.{
        b.fmt("qemu-system-{s}", .{@tagName(arch)}),
        "-drive",
    });
    qemu.addPrefixedFileArg("format=raw,file=", imgFile);
    qemu.addArgs(&.{
        "-d",
        "int,cpu_reset",
        "--no-reboot",
        // "--no-shutdown",
        "-smp",
        "4,cores=4",
        "-M",
        "type=q35,smm=off,hpet=on", // q35 has HPET by default afaik but better safe than sorry
        "-cpu",
        "qemu64,la57,invtsc,pdpe1gb,rdrand",
        "-m",
        "4G",
    });

    if (b.option(bool, "qemu-no-accel", "disable native accel for qemu") != true) {
        switch (b.graph.host.result.os.tag) {
            .windows => qemu.addArgs(&.{ "-accel", "whpx" }),
            .linux => qemu.addArgs(&.{ "-accel", "kvm" }),
            .macos => qemu.addArgs(&.{ "-accel", "hvf" }),
            else => {},
        }
    }

    qemu.setCwd(b.path("test"));
    qemu.stdio = .inherit;

    if (b.option(bool, "debugcon", "output ports to stdio") orelse true) {
        qemu.addArg("-debugcon");
        qemu.addArg("file:aaa.txt");
    }
    switch (parseQemuGdbOption(b.option([]const u8, "gdb", "use gdb with qemu"))) {
        .none => {},
        .default => {
            qemu.addArgs(&.{ "-s", "-S" });
        },
        .port => |p| {
            qemu.addArgs(&.{ "-gdb", b.fmt("tcp:{d}", .{p}), "-S" });
        },
    }

    qemu.step.dependOn(imgstep);

    const run = b.step("qemu", "Run the OS in qemu");
    run.dependOn(&qemu.step);

    try usr(b, arch, target, optimize);

    const test_step = b.step("test", "Run tests.");
    const util_test = b.addTest(.{
        .root_source_file = b.path("src/util/util.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = optimize,
    });
    const run_util_test = b.addRunArtifact(util_test);
    test_step.dependOn(&run_util_test.step);
    if (zuid_dep.builder.top_level_steps.get("test")) |zuid_tests| {
        test_step.dependOn(&zuid_tests.step);
    }
}
