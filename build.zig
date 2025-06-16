const std = @import("std");
const log = std.log;
const Target = std.Target;
const Build = std.Build;
const LazyPath = Build.LazyPath;

const utils = @import("build/util.zig");
const add_krnl = @import("build/krnl.zig").add_krnl;
const add_stage2 = @import("build/ldr.zig").add_stage2;

fn target_features(query: *Target.Query) !void {
    query.cpu_model = .{ .explicit = std.Target.Cpu.Model.generic(query.cpu_arch.?) };
    switch (query.cpu_arch.?) {
        .x86_64 => {
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
        },
        else => return error.invalid_imaginarium_arch,
    }
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

fn add_tools(b: *Build) *Build.Step.Compile {
    const zigimg = b.dependency("zigimg", .{
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
    const tools_module = b.createModule(.{
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
        .root_source_file = b.path("src/tools/main.zig"),
    });
    tools_module.addImport("zigimg", zigimg.module("zigimg"));
    return b.addExecutable(.{
        .name = "imagtools",
        .root_module = tools_module,
    });
}

const complex_img = @import("disk_image_step");
const ImgInterface = complex_img.BuildInterface;

fn add_img(b: *Build, arch: Target.Cpu.Arch, krnlstep: *Build.Step, elf: LazyPath, symbols: ?LazyPath) !struct { *Build.Step, LazyPath, bool } {
    const limine = b.dependency("zig_limine_install", .{ .target = b.resolveTargetQuery(.{}), .optimize = .ReleaseSafe });

    // const limine_files = limine.namedLazyPath("limine-bios.sys")

    const efi: bool = b.option(bool, "efi", "Use EFI boot? Implies -Dgpt") orelse false;
    const gpt: bool = b.option(bool, "gpt", "Use GPT partitioning") orelse efi;

    if (efi and !gpt) {
        std.log.err("Cannot EFI boot without GPT partitioning", .{});
        b.invalid_user_input = true;
        @panic("");
    }

    const builder = ImgInterface.init(b, b.dependencyFromBuildZig(complex_img, .{}));

    var fs: ImgInterface.FileSystemBuilder = .init(b);
    fs.copyFile(b.path("src/krnl/boot/limine.conf"), "/limine.conf");
    fs.copyFile(elf, "/imaginarium.elf");
    if (symbols) |d| {
        fs.copyFile(d, "/krnl.dbg");
    }
    fs.copyFile(limine.namedLazyPath("limine-bios.sys"), "/limine-bios.sys");
    {
        fs.mkdir("/EFI");
        fs.mkdir("/EFI/BOOT");
        fs.copyFile(limine.namedLazyPath("limine").path(b, "BOOTX64.EFI"), "/EFI/BOOT/BOOTX64.EFI");
    }

    const content: ImgInterface.Content = if (gpt) .{ .gpt_part_table = .{ .partitions = &.{
        .{
            .type = .{ .guid = "21686148-6449-6E6F-744E-656564454649".* },
            .name = "\"Legacy bootloader\"",
            .size = 0x8000,
            .offset = 0x5000,
            .data = .empty,
        },
        .{
            .type = .{ .name = .@"efi-system" },
            .name = "\"EFI System Partition\"",
            .offset = 0xD000,
            .size = 0x210_0000,
            .data = .{
                .vfat = .{
                    .format = .fat32,
                    .label = "ROOTFS",
                    .tree = fs.finalize(),
                },
            },
        },
    } } } else .{
        .mbr_part_table = .{
            .partitions = .{
                &.{
                    .type = .@"fat16-lba",
                    .bootable = true,
                    .size = null,
                    .offset = 0x8000,
                    .data = .{
                        .vfat = .{
                            .format = .fat16,
                            .label = "ROOTFS",
                            .tree = fs.finalize(),
                        },
                    },
                },
                null,
                null,
                null,
            },
        },
    };
    const img_file = builder.createDisk(0x212_0000, content);

    const limine_bin = limine.artifact("limine-install");

    const add_limine_to_image = b.addRunArtifact(limine_bin);
    add_limine_to_image.addArg("-i");
    add_limine_to_image.addFileArg(img_file);
    add_limine_to_image.addArg("-o");
    const img2 = add_limine_to_image.addOutputFileArg("image.bin");
    if (gpt) {
        add_limine_to_image.addArgs(&.{ "-p", "1" });
    }

    const step = b.step("img", "create bootable disk image for the target");
    utils.installFrom(b, &add_limine_to_image.step, step, img2, b.fmt("{s}/img", .{@tagName(arch)}), "drive.bin");

    const copyToTestDir = b.addUpdateSourceFiles();
    copyToTestDir.step.dependOn(&add_limine_to_image.step);
    copyToTestDir.step.dependOn(krnlstep);
    copyToTestDir.addCopyFileToSource(img2, "test/drive.bin");
    if (symbols) |d| {
        copyToTestDir.addCopyFileToSource(d, "test/krnl.debug");
    }
    step.dependOn(&copyToTestDir.step);
    return .{ step, img2, efi };
}

pub fn build(b: *Build) !void {
    utils.init(b);
    const arch = b.option(Target.Cpu.Arch, "arch", "The CPU architecture to build for") orelse .x86_64;
    var selected_target: Target.Query = .{
        .abi = .none,
        .os_tag = .freestanding,
        .cpu_arch = arch,
    };
    try target_features(&selected_target);
    const target = b.resolveTargetQuery(selected_target);
    selected_target.dynamic_linker = .init("IMAG:PREKERNEL");
    selected_target.os_tag = .other;
    const krnltgt = b.resolveTargetQuery(selected_target);

    const optimize = b.standardOptimizeOption(.{});

    const max_ioapics = b.option(u32, "max-ioapics", "maximum number of ioapics supported (default 5)") orelse 5;
    const max_hpets = b.option(u32, "max-hpets", "maximum number of HPET blocks supported (default 1)") orelse 1;
    const force_hypervisor = b.option(bool, "force-hypervisor", "force assume a hypervisor is present (running in a VM, default false)") orelse false;

    const options = b.addOptions();
    options.addOption(u32, "max_ioapics", max_ioapics);
    options.addOption(u32, "max_hpets", max_hpets);
    options.addOption(usize, "max_elf_size", 1 << 30);
    options.addOption(bool, "rsdp_search_bios", true);
    options.addOption(bool, "force_hypervisor", force_hypervisor);

    const optsModule = options.createModule();
    utils.name_module("config", optsModule);

    const zuid_dep = b.dependency("zuid", .{});
    utils.name_module("zuid", zuid_dep.module("zuid"));

    const util = b.createModule(.{
        .root_source_file = b.path("src/util/util.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = optimize,
    });
    utils.name_module("util", util);
    utils.addImportFromTable(util, "config");
    utils.addImportFromTable(util, "zuid");

    const collections = b.createModule(.{
        .root_source_file = b.path("libs/collections/collections.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = optimize,
    });
    utils.name_module("collections", collections);
    utils.addImportFromTable(collections, "util");

    const common_module = b.createModule(.{
        .root_source_file = b.path("src/cmn/common.zig"),
    });
    utils.name_module("cmn", common_module);
    const tools = add_tools(b);

    // const aaa = b.step("aaa", "");
    const fontgen = b.addRunArtifact(tools);
    fontgen.addArg("font");
    fontgen.addFileArg(b.path("monofont.png"));
    const zon = fontgen.addOutputFileArg("font.zon");
    // aaa.dependOn(&b.addInstallFile(zon, "aaa").step);

    const krnlexe, const krnlstep, const elf, const debug = try add_krnl(b, arch, krnltgt, optimize, zon);
    const stage2exe, const stage2step, const s2elf, const s2debug = try add_stage2(b, arch, target, optimize);
    _ = stage2exe; // autofix
    _ = stage2step; // autofix
    _ = s2elf; // autofix
    _ = s2debug; // autofix
    const imgstep, const imgFile, const efi = try add_img(b, arch, krnlstep, elf, debug);

    var cpu_flags = try std.ArrayList([]const u8).initCapacity(b.allocator, 12);
    cpu_flags.appendSliceAssumeCapacity(&.{ "qemu64", "+invtsc", "+pdpe1gb", "+rdrand", "+arat", "+rdseed", "+hypervisor" });

    const qemu = b.addSystemCommand(&.{
        b.fmt("qemu-system-{s}", .{@tagName(arch)}),
    });

    // the version of OVMF we get doesnt have CSM so we can only use it when EFI booting.
    if (efi) {
        const ovmf = b.lazyDependency("ovmf", .{}) orelse return;
        const copy = b.addWriteFiles();
        const code = copy.addCopyFile(ovmf.path("ovmf-code-x86_64.fd"), "ovmf-code.fd");
        const vars = copy.addCopyFile(ovmf.path( "ovmf-vars-x86_64.fd"), "ovmf-vars.fd");
        qemu.step.dependOn(&copy.step);

        qemu.addArg("-drive");
        qemu.addPrefixedFileArg("if=pflash,unit=0,format=raw,readonly=on,file=", code);
        qemu.addArg("-drive");
        qemu.addPrefixedFileArg("if=pflash,unit=1,format=raw,file=", vars);
    }

    qemu.addArg("-drive");
    qemu.addPrefixedFileArg("id=bootdisk,format=raw,if=none,file=", imgFile);

    if (b.option(bool, "qemu-no-accel", "disable native accel for qemu") != true) {
        switch (b.graph.host.result.os.tag) {
            .windows => qemu.addArgs(&.{ "-accel", "whpx" }),
            .linux => {
                // cpu_flags.items[0] = "host";
                qemu.addArgs(&.{ "-accel", "kvm" });
                cpu_flags.appendAssumeCapacity("+x2apic");
                // cpu_flags.appendAssumeCapacity("migratable=off");
            },
            .macos => qemu.addArgs(&.{ "-accel", "hvf" }),
            else => {},
        }
    }

    qemu.addArgs(&.{
        "-d",
        "int,guest_errors",
        "--no-reboot",
        // "--no-shutdown",
        // "-smp",
        // "4,cores=4",
        "-M",
        "type=q35,smm=off,hpet=on", // q35 has HPET by default afaik but better safe than sorry
        "-cpu",
        try std.mem.join(b.allocator, ",", try cpu_flags.toOwnedSlice()),
        "-m",
        "2G",
        "-device",
        "nvme,serial=deadbeef,drive=bootdisk",
        // "-chardev",
        // "file,id=bios-logs,path=aaabios.txt",
        // "-device",
        // "isa-debugcon,iobase=0x402,chardev=bios-logs",
        // "-serial",
        // "stdio",
    });

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

    if (b.args) |args| {
        qemu.addArgs(args);
    }

    qemu.step.dependOn(imgstep);

    const run = b.step("qemu", "Run the OS in qemu");
    run.dependOn(&qemu.step);

    const test_step = b.step("test", "Run tests.");

    const util_test = b.addTest(.{ .root_module = util });
    const run_util_test = b.addRunArtifact(util_test);
    test_step.dependOn(&run_util_test.step);

    const collections_test = b.addTest(.{ .root_module = collections });
    const run_collections_test = b.addRunArtifact(collections_test);
    test_step.dependOn(&run_collections_test.step);

    if (zuid_dep.builder.top_level_steps.get("test")) |zuid_tests| {
        test_step.dependOn(&zuid_tests.step);
    }

    const noemit = b.step("buildnoemit", "");
    noemit.dependOn(&krnlexe.step);
    noemit.dependOn(&tools.step);
    // noemit.dependOn(&stage2exe.step);
}
