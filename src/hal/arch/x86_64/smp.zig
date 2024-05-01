const msr = @import("msr.zig");
const util = @import("util");

const ext = util.extern_address;

pub const ap_start = ext("__ap_trampoline_begin");
pub const ap_end = ext("__ap_trampoline_end");

export var __bsp_start_spinlock_flag: u8 = 0;

pub fn SmpUtil(comptime LocalControlBlock: type) type {
    return struct {
        pub const LocalControlBlockPointer = *addrspace(.gs) LocalControlBlock;
        pub const lcb: *addrspace(.gs) LocalControlBlock = @ptrFromInt(@alignOf(LocalControlBlock));

        pub fn setup(base_linear_addr: isize) void {
            msr.write(.gs_base, base_linear_addr);
        }
    };
}

export fn __ap_landing() noreturn {
    @import("gdt.zig").apply();
    @import("idt.zig").load();
    while(true) {}
}