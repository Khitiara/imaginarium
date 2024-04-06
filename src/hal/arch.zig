pub usingnamespace switch (@import("builtin").cpu.arch) {
    .aarch64 => struct {
        pub const aarch64 = @import("arch/aarch64.zig");
        pub const cc = aarch64.cc;
        pub const platform_init = aarch64.platform_init;
    },
    .x86_64 => struct {
        pub const x86_64 = @import("arch/x86_64.zig");
        pub const cc = x86_64.cc;
        pub const platform_init = x86_64.platform_init;
    },
    else => |arch| @compileError("Unsupported architecture " ++ @tagName(arch)),
};

test {
    @import("std").testing.refAllDecls(@This());
}
