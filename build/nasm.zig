const std = @import("std");
const Target = std.Target;
const Build = std.Build;
const LazyPath = Build.LazyPath;

pub fn buildAsmFile(b: *Build, file: LazyPath, output_name: []const u8) LazyPath {
    const step = b.addSystemCommand(&.{"nasm", "-f", "elf64", "-g"});
    step.step.name = b.dupe("build nasm assembly file");
    step.addFileArg(file);
    return step.addPrefixedOutputFileArg("-o", output_name);
}