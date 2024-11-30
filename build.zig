const std = @import("std");
const log = std.log;
const Target = std.Target;
const DiskImage = @import("build/disk_image.zig");
const Build = std.Build;
const LazyPath = Build.LazyPath;

const utils = @import("build/util.zig");
const add_krnl = @import("build/krnl.zig").add_krnl;
const add_stage2 = @import("build/ldr.zig").add_stage2;
const uacpi = @import("build/uacpi.zig");

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
            query.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));
        },
        .aarch64 => {
            // for now nothing, idk what needs tweaking here
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

fn add_img(b: *Build, arch: Target.Cpu.Arch, krnlstep: *Build.Step, elf: LazyPath, symbols: ?LazyPath) !struct { *Build.Step, LazyPath } {
    const ldr_img = b.dependency("bootelf", .{}).namedWriteFiles("bootelf").getDirectory().path(b, "bootelf.bin");
    const disk_image = DiskImage.create(b, .{
        .basename = "drive.bin",
    });
    disk_image.append(ldr_img);
    disk_image.append(elf);
    disk_image.step.dependOn(krnlstep);

    b.getInstallStep().dependOn(&disk_image.step);

    const step = b.step("img", "create bootable disk image for the target");
    utils.installFrom(b, &disk_image.step, step, disk_image.getOutput(), b.fmt("{s}/img", .{@tagName(arch)}), disk_image.basename);

    const copyToTestDir = b.addUpdateSourceFiles();
    copyToTestDir.step.dependOn(&disk_image.step);
    copyToTestDir.step.dependOn(krnlstep);
    copyToTestDir.addCopyFileToSource(disk_image.getOutput(), "test/drive.bin");
    if (symbols) |d| {
        copyToTestDir.addCopyFileToSource(d, "test/krnl.debug");
    }
    step.dependOn(&copyToTestDir.step);
    return .{ step, disk_image.getOutput() };
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
    const optimize = b.standardOptimizeOption(.{});
    uacpi.add_uacpi_to_build(b, target, optimize);

    const max_ioapics = b.option(u32, "max_ioapics", "maximum number of ioapics supported (default 5)") orelse 5;
    const max_hpets = b.option(u32, "max_hpets", "maximum number of HPET blocks supported (default 1)") orelse 1;

    const options = b.addOptions();
    options.addOption(u32, "max_ioapics", max_ioapics);
    options.addOption(u32, "max_hpets", max_hpets);
    options.addOption(usize, "max_elf_size", 1 << 30);
    options.addOption(bool, "rsdp_search_bios", true);

    const optsModule = options.createModule();
    utils.name_module("config", optsModule);

    const zuid_dep = b.dependency("zuid", .{});
    utils.name_module("zuid", zuid_dep.module("zuid"));

    const util = b.createModule(.{
        .root_source_file = b.path("src/util/util.zig"),
    });
    utils.name_module("util", util);
    utils.addImportFromTable(util, "config");
    utils.addImportFromTable(util, "zuid");

    const common_module = b.createModule(.{
        .root_source_file = b.path("src/cmn/common.zig"),
    });
    utils.name_module("cmn", common_module);

    const krnlexe, const krnlstep, const elf, const debug = try add_krnl(b, arch, target, optimize);
    const stage2exe, const stage2step, const s2elf, const s2debug = try add_stage2(b, arch, target, optimize);
    _ = stage2step; // autofix
    _ = s2elf; // autofix
    _ = s2debug; // autofix
    const imgstep, const imgFile = try add_img(b, arch, krnlstep, elf, debug);

    var cpu_flags = try std.ArrayList([]const u8).initCapacity(b.allocator, 8);
    cpu_flags.appendSliceAssumeCapacity(&.{ "qemu64", "+la57", "+invtsc", "+pdpe1gb", "+rdrand", "+arat", "+rdseed" });

    const qemu = b.addSystemCommand(&.{
        b.fmt("qemu-system-{s}", .{@tagName(arch)}),
        "-drive",
    });
    qemu.addPrefixedFileArg("format=raw,file=", imgFile);

    if (b.option(bool, "qemu-no-accel", "disable native accel for qemu") != true) {
        switch (b.graph.host.result.os.tag) {
            .windows => qemu.addArgs(&.{ "-accel", "whpx" }),
            .linux => {
                qemu.addArgs(&.{ "-accel", "kvm" });
                cpu_flags.appendAssumeCapacity("+x2apic");
            },
            .macos => qemu.addArgs(&.{ "-accel", "hvf" }),
            else => {},
        }
    }

    qemu.addArgs(&.{
        "-d",
        "int,cpu_reset,guest_errors",
        "--no-reboot",
        // "--no-shutdown",
        // "-smp",
        // "4,cores=4",
        "-M",
        "type=q35,smm=off,hpet=on", // q35 has HPET by default afaik but better safe than sorry
        "-cpu",
        try std.mem.join(b.allocator, ",", try cpu_flags.toOwnedSlice()),
        "-m",
        "4G",
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

    qemu.step.dependOn(imgstep);

    const run = b.step("qemu", "Run the OS in qemu");
    run.dependOn(&qemu.step);

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

    const noemit = b.step("buildnoemit", "");
    noemit.dependOn(&krnlexe.step);
    noemit.dependOn(&stage2exe.step);
}
