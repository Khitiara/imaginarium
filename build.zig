const std = @import("std");
const log = std.log;
const Target = std.Target;

fn tgtOption(b: *std.Build) std.Build.ResolvedTarget {
    const default: Target.Query = .{
        .abi = .none,
        .os_tag = .freestanding,
        .cpu_arch = .x86_64,
    };
    const arch = b.option(Target.Cpu.Arch, "arch", "The CPU architecture to build for") orelse .x86_64;
    const triple = std.fmt.allocPrint(b.allocator, "{s}-freestanding-none", .{@tagName(arch)}) catch {
        log.err("Out of memory formatting target triple", .{});
        return b.resolveTargetQuery(default);
    };
    const mcpu = b.option([]const u8, "cpu", "Target CPU features to add or subtract");
    var diags: Target.Query.ParseOptions.Diagnostics = .{};
    const selected_target = Target.Query.parse(.{
        .arch_os_abi = triple,
        .cpu_features = mcpu,
        .diagnostics = &diags,
        .object_format = "elf",
    }) catch |err| blk: {
        switch (err) {
            error.UnknownCpuModel => {
                log.err("Unknown CPU: '{s}'\nAvailable CPUs for architecture '{s}':", .{
                    diags.cpu_name.?,
                    @tagName(diags.arch.?),
                });
                for (diags.arch.?.allCpuModels()) |cpu| {
                    log.err(" {s}", .{cpu.name});
                }
            },
            error.UnknownCpuFeature => {
                log.err(
                    \\Unknown CPU feature: '{s}'
                    \\Available CPU features for architecture '{s}':
                    \\
                , .{
                    diags.unknown_feature_name.?,
                    @tagName(diags.arch.?),
                });
                for (diags.arch.?.allFeaturesList()) |feature| {
                    log.err(" {s}: {s}", .{ feature.name, feature.description });
                }
            },
            error.UnknownOperatingSystem => unreachable,
            else => |e| {
                log.err("Unable to parse target '{s}': {s}\n", .{ triple, @errorName(e) });
            },
        }
        break :blk default;
    };
    return b.resolveTargetQuery(selected_target);
}

pub fn build(b: *std.Build) void {
    const target = tgtOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const name = switch (target.result.cpu.arch) {
        inline else => |arch| "imaginarium." ++ @tagName(arch) ++ ".elf",
    };

    const hal = b.addModule("hal", .{
        .root_source_file = .{ .path = "src/hal/hal.zig" },
        .code_model = .kernel,
        .target = target,
        .optimize = optimize,
        .strip = true,
    });

    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = "src/knl/main.zig" },
        .target = target,
        .optimize = optimize,
        .strip = true,
        .code_model = .kernel,
    });

    exe.root_module.addImport("hal", hal);

    exe.setLinkerScriptPath(.{ .path = "src/knl/link.ld" });

    b.installArtifact(exe);

    // const exe_unit_tests = b.addTest(.{
    //     .root_source_file = .{ .path = "src/knl/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    //     .strip = true,
    // });
    // exe_unit_tests.root_module.addImport("hal", hal);

    // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_exe_unit_tests.step);
}
