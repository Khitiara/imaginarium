pub usingnamespace switch (@import("builtin").cpu.arch) {
    .aarch64 => struct {
        pub const aarch64 = @import("arch/aarch64.zig");
        pub const cc = aarch64.cc;
    },
    .x86_64 => struct {
        pub const x86_64 = @import("arch/x86_64.zig");
        pub const cc = x86_64.cc;
    },
    else => |arch| @compileError("Unsupported architecture " ++ @tagName(arch)),
};

test {
    @import("std").testing.refAllDecls(@This());
}
