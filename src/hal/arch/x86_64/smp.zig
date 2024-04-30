const msr = @import("msr.zig");

pub fn SmpUtil(comptime LocalControlBlock: type) type {
    return struct {
        pub const LocalControlBlockPointer = *addrspace(.gs) LocalControlBlock;
        pub const lcb: *addrspace(.gs) LocalControlBlock = @ptrFromInt(@alignOf(LocalControlBlock));

        pub fn setup(base_linear_addr: isize) void {
            msr.write(.gs_base, base_linear_addr);
        }
    };
}
