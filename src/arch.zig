pub usingnamespace switch (@import("builtin").cpu.arch) {
    .aarch64 => struct {
        pub const aarch64 = @import("arch/aarch64.zig");
    },
    .x86_64 => struct {
        pub const x86_64 = @import("arch/x86_64.zig");
    },
    else => |arch| @compileError("Unsupported architecture " ++ @tagName(arch)),
};
