const std = @import("std");

pub fn add(b: *std.Build, arch: std.Target.Cpu.Arch, optimize: std.builtin.OptimizeMode, options: *std.Build.Module, util: *std.Build.Module, hal: *std.Build.Module) void {
    const target = b.resolveTargetQuery(.{
        .abi = .msvc,
        .os_tag = .uefi,
        .cpu_arch = arch,
    });

    const ldr_efi = b.addExecutable(.{
        .name = "bootx64",
        .root_source_file = .{ .path = "src/ldr/efi/efimain.zig" },
        .code_model = .kernel,
        .target = target,
        .optimize = optimize,
    });

    ldr_efi.root_module.addImport("hal", hal);
    ldr_efi.root_module.addImport("util", util);
    ldr_efi.root_module.addImport("config", options);

    const step = b.step("ldr", "bootloader");
    var install = b.addInstallArtifact(ldr_efi, .{
        .dest_dir = .{.override = .{ .custom = "ldr" }},
    });
    step.dependOn(&install.step);
    b.getInstallStep().dependOn(step);
}
