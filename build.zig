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
        inline else => |a| "imaginarium." ++ @tagName(a) ++ ".krnl.b",
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

    const krnlstep = b.step("kernel", "imaginarium kernel");
    krnlstep.dependOn(&b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "krnl" } },
    }).step);
    b.getInstallStep().dependOn(krnlstep);

    const lib_name = switch (arch) {
        inline else => |a| "imaginarium." ++ @tagName(a) ++ ".usr.l",
    };
    const dynlib_name = switch (arch) {
        inline else => |a| "imaginarium." ++ @tagName(a) ++ ".usr.dyn",
    };

    const usr = b.addStaticLibrary(.{
        .name = lib_name,
        .root_source_file = .{ .path = "src/usr/usr_lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    usr.out_lib_filename = b.dupe(usr.name);

    // cant create from existing module so invert that and create the object first
    const usr_imports = b.addObject(.{
        .name = dynlib_name,
        .root_source_file = .{ .path = "src/usr/usr_lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    usr_imports.root_module.addImport("hal", hal);
    usr_imports.root_module.addImport("util", util);
    usr_imports.root_module.addImport("config", optsModule);

    // cant create an object compile step from an existing module so get the root module of the object step
    // and add that manually to the modules map
    b.modules.put("usr", &usr_imports.root_module) catch @panic("OOM");

    const usrstep = b.step("usr", "usermode kernel services");
    usrstep.dependOn(&b.addInstallArtifact(usr, .{
        .dest_dir = .{ .override = .{ .custom = "usr" } },
    }).step);
    usrstep.dependOn(&b.addInstallFile(.{ .path = "src/usr/usr.zig" }, "usr/include/usr.zig").step);
    usrstep.dependOn(&b.addInstallFile(.{ .path = "src/usr/usr.h" }, "usr/include/usr.h").step);
    usrstep.dependOn(&usr_imports.step);

    b.getInstallStep().dependOn(usrstep);
}
