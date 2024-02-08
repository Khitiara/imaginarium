const std = @import("std");
const log = std.log;
const Target = std.Target;

const ldr = @import("src/ldr/build.zig");

pub fn build(b: *std.Build) void {
    const arch = b.option(Target.Cpu.Arch, "arch", "The CPU architecture to build for") orelse .x86_64;
    const selected_target: Target.Query = .{
        .abi = .none,
        .os_tag = .freestanding,
        .cpu_arch = arch,
    };
    const target = b.resolveTargetQuery(selected_target);
    const optimize = b.standardOptimizeOption(.{});

    const max_ioapics = b.option(u32, "max_ioapics", "maximum number of ioapics supported (default 5)") orelse 5;

    const options = b.addOptions();
    options.addOption(u32, "max_ioapics", max_ioapics);

    const optsModule = options.createModule();

    const util = b.createModule(.{
        .root_source_file = .{ .path = "src/util/util.zig" },
    });

    util.addImport("config", optsModule);

    const hal = b.createModule(.{
        .root_source_file = .{ .path = "src/hal/hal.zig" },
    });
    hal.addImport("util", util);
    hal.addImport("config", optsModule);

    ldr.add(b, arch, optimize, optsModule, util, hal);

    const name = switch (arch) {
        inline else => |a| "imaginarium." ++ @tagName(a) ++ ".elf",
    };

    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = "src/krnl/main.zig" },
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
    });

    exe.root_module.addImport("hal", hal);
    exe.root_module.addImport("util", util);
    exe.root_module.addImport("config", optsModule);

    exe.setLinkerScriptPath(.{ .path = "src/krnl/link.ld" });

    b.installArtifact(exe);

    // const exe_unit_tests = b.addTest(.{
    //     .root_source_file = .{ .path = "src/krnl/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    //     .strip = true,
    // });
    // exe_unit_tests.root_module.addImport("hal", hal);

    // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_exe_unit_tests.step);
}
