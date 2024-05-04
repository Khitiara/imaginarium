const Thread = @import("Thread.zig");
const hal = @import("hal");
const arch = hal.arch;
const apic = hal.apic;
const std = @import("std");

pub const LocalControlBlock = extern struct {
    current_thread: ?*Thread = null,
    syscall_stack: *anyopaque = undefined,
    kernel_stack: *anyopaque = undefined,
};

pub var lcbs: []LocalControlBlock = undefined;
const hal_smp = arch.smp.SmpUtil(LocalControlBlock);
pub const lcb = hal_smp.lcb;

pub fn allocate_lcbs(alloc: std.mem.Allocator) void {
    lcbs = alloc.alignedAlloc(LocalControlBlock, 1 << 12, apic.processor_count);
    @memset(lcbs, .{});
    set_lcb_base(@bitCast(@intFromPtr(&lcbs[apic.lapic_indices[apic.get_lapic_id()]])));
}

pub fn set_lcb_base(addr: isize) void {
    hal_smp.setup(addr);
}
