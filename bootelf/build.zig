const std = @import("std");

pub fn build(b: *std.Build) !void {
    var make = if (b.graph.host.result.os.tag != .windows) blk: {
        const nasm = b.dependency("nasm", .{ .target = @as([]const u8, "native") });
        const nasm_exe = nasm.artifact("nasm");

        break :blk b.addRunArtifact(nasm_exe);
    } else b.addSystemCommand(&.{try b.findProgram(&.{"nasm"}, &.{})});

    make.addFileInput(b.path("framebuffer.asm"));
    make.addFileInput(b.path("elf_load.asm"));
    make.addFileInput(b.path("memmap.asm"));
    make.addFileInput(b.path("paging.asm"));

    make.addPrefixedDirectoryArg("-i", b.path("."));

    make.setName("make bootelf");
    make.addFileArg(b.path("bootelf.asm"));
    const loader_bin_path = make.addPrefixedOutputFileArg("-o", "bootelf.bin");
    // make.addArg("-MD");
    // make.addArg("-MF");
    // _ = make.addDepFileOutputArg("bootelf.d");

    const write = b.addNamedWriteFiles("bootelf");
    _ = write.addCopyFile(loader_bin_path, "bootelf.bin");
}
