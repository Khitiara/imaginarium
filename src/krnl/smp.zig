const Thread = @import("thread/Thread.zig");
const dispatcher = @import("dispatcher/dispatcher.zig");
const hal = @import("hal");
const arch = hal.arch;
const apic = hal.apic;
const std = @import("std");
const util = @import("util");
const queue = util.queue;

pub const LocalControlBlock = extern struct {
    current_thread: ?*Thread = null,
    standby_thread: ?*Thread = null,
    syscall_stack: *anyopaque = undefined,
    kernel_stack: *anyopaque = undefined,
    local_dispatcher_queue: queue.PriorityQueue(Thread, "scheduler_hook", "priority", Thread.Priority) = .{},
    local_dispatcher_lock: util.SpinLock = .{},
    irql: dispatcher.InterruptRequestPriority = .passive,
    irql_lock: util.SpinLock = .{},
    dpc_queue: queue.PriorityQueue(dispatcher.Dpc, "hook", "priority", dispatcher.Dpc.Priority) = .{},
    dpc_lock: util.SpinLock = .{},
    frame: ?*arch.SavedRegisterState = null,
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
