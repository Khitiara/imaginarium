const thread = @import("thread.zig");
const hal = @import("hal");
const arch = hal.arch;

pub const LocalControlBlock = extern struct {
    current_thread: ?*thread.Tcb = null,
    syscall_stack: *anyopaque = undefined,
};

const hal_smp = arch.smp.SmpUtil(LocalControlBlock);
pub const lcb = hal_smp.lcb;

pub fn set_lcb_base(addr: isize) void {
    hal_smp.setup(addr);
}