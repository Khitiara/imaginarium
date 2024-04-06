pub const cpuid = @import("x86_64/cpuid.zig");
pub const msr = @import("x86_64/msr.zig");
pub const segmentation = @import("x86_64/segmentation.zig");
pub const paging = @import("x86_64/paging.zig");
pub const control_registers = @import("x86_64/ctrl_registers.zig");
pub const serial = @import("x86_64/serial.zig");
pub const descriptors = @import("x86_64/descriptors.zig");

pub const cc: @import("std").builtin.CallingConvention = .SysV;

comptime {
    _ = @import("x86_64/init.zig");
}

pub const Flags = packed struct(u64) {
    carry: bool,
    _reserved1: u1 = 1,
    parity: bool,
    _reserved2: u1 = 0,
    aux_carry: bool,
    _reserved3: u1 = 0,
    zero: bool,
    sign: bool,
    trap: bool,
    interrupt_enable: bool,
    direction: bool,
    overflow: bool,
    iopl: u2,
    nt: bool,
    mode: bool,
    res: bool,
    vm: bool,
    alignment_check: bool,
    vif: bool,
    vip: bool,
    cpuid: bool,
    _reserved4: u8 = 0,
    aes_keyschedule_loaded: bool,
    alternate_instruction_set: bool,
    _reserved5: u32 = 0,
};

pub fn flags() Flags {
    return asm volatile (
        \\pushfq
        \\pop %[flags]
        : [flags] "=r" (-> Flags),
    );
}

pub fn setflags(f: Flags) void {
    asm volatile (
        \\push %[flags]
        \\popfq
        :
        : [flags] "r" (f),
        : "flags"
    );
}

test {
    @import("std").testing.refAllDecls(@This());
}
