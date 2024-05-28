const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b;
}

var make_out: ?std.Build.LazyPath = null;

pub fn make_bootelf(b: *std.Build) !std.Build.LazyPath {
    if (make_out) |f| {
        return f;
    }

    const this_dep = b.dependencyFromBuildZig(@This(), .{});
    var make = if (b.graph.host.result.os.tag != .windows) blk: {
        const nasm = this_dep.builder.dependency("nasm", .{ .target = @as([]const u8, "native") });
        const nasm_exe = nasm.artifact("nasm");

        break :blk b.addRunArtifact(nasm_exe);
    } else b.addSystemCommand(&.{"nasm"});

    make.extra_file_dependencies = &.{
        "bootelf/framebuffer.asm",
        "bootelf/elf_load.asm",
        "bootelf/memmap.asm",
        "bootelf/paging.asm",
        "bootelf/bootelf.asm",
    };
    make.setCwd(this_dep.path("."));

    make.setName("make bootelf");
    make.addArg("bootelf.asm");
    make.addArg("-o");
    const loader_bin_path = make.addOutputFileArg("bootelf.bin");
    // make.addArg("-MG");
    // make.addArg("-MF");
    // _ = make.addDepFileOutputArg("bootelf.d");
    // make.addArg("-MT");
    // make.addArg("bootelf");
    // make.addArg("-MW");

    const install_loader = b.addInstallFileWithDir(loader_bin_path, .{ .custom = "x86_64/ldr" }, "bootelf.bin");
    install_loader.step.name = "install bootelf.bin";
    b.getInstallStep().dependOn(&install_loader.step);
    make_out = loader_bin_path;
    return loader_bin_path;
}
