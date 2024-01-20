const std = @import("std");
const Target = std.Target;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .whitelist = &[_]Target.Query{
            .{
                .abi = .none,
                .os_tag = .freestanding,
                .cpu_arch = .x86_64,
            },
            .{
                .abi = .none,
                .os_tag = .freestanding,
                .cpu_arch = .aarch64,
            },
        },
        .default_target = .{
            .abi = .none,
            .os_tag = .freestanding,
            .cpu_arch = .x86_64,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const name = switch (target.result.cpu.arch) {
        inline else => |arch| "imaginarium." ++ @tagName(arch) ++ ".elf",
    };

    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .strip = true,
        .code_model = .kernel,
    });

    exe.setLinkerScriptPath(.{ .path = "src/link.ld" });

    b.installArtifact(exe);
}
