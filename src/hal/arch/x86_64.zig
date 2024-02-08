pub const cpuid = @import("x86_64/cpuid.zig");
pub const msr = @import("x86_64/msr.zig");
pub const segmentation = @import("x86_64/segmentation.zig");
pub const paging = @import("x86_64/paging.zig");
pub const control_registers = @import("x86_64/ctrl_registers.zig");

pub fn flags() u64 {
    return asm volatile (
        \\pushfq
        \\pop %[flags]
        : [flags] "=r" (-> u64),
    );
}

test {
    @import("std").testing.refAllDecls(@This());
}
