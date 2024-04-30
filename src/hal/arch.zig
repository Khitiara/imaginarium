pub usingnamespace switch (@import("builtin").cpu.arch) {
    .aarch64 => struct {
        pub const aarch64 = @import("arch/aarch64.zig");
        pub const cc = aarch64.cc;
        pub const platform_init = aarch64.platform_init;

        pub fn phys_mem_base() isize {
            return undefined;
        }
    },
    .x86_64 => struct {
        pub const x86_64 = @import("arch/x86_64.zig");
        pub const cc = x86_64.cc;
        pub const platform_init = x86_64.platform_init;
        pub const puts = x86_64.puts;
        pub const ptr_from_physaddr = x86_64.ptr_from_physaddr;

        pub const serial = x86_64.serial;

        pub const get_and_disable_interrupts = x86_64.idt.get_and_disable;
        pub const restore_interrupt_state = x86_64.idt.restore;

        pub const spin_hint = x86_64.pause;

        pub const smp = x86_64.smp;

        pub fn phys_mem_base() isize {
            return x86_64.pmm.phys_mapping_base;
        }
    },
    else => |arch| @compileError("Unsupported architecture " ++ @tagName(arch)),
};

test {
    @import("std").testing.refAllDecls(@This());
}
