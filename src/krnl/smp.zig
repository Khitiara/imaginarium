const Thread = @import("thread/Thread.zig");
const dispatcher = @import("dispatcher/dispatcher.zig");
const hal = @import("hal");
const arch = hal.arch;
const apic = hal.apic;
const std = @import("std");
const util = @import("util");
const queue = util.queue;
const zuid = @import("zuid");

pub const idle_thread_id = zuid.null_uuid;

pub const LocalControlBlock = struct {
    current_thread: ?*Thread = null,
    standby_thread: ?*Thread = null,
    idle_thread: *Thread = undefined,
    syscall_stack: *anyopaque = undefined,
    local_dispatcher_queue: queue.PriorityQueue(Thread, "scheduler_hook", "priority", Thread.Priority) = .{},
    local_dispatcher_lock: hal.SpinLock = .{},
    irql: dispatcher.InterruptRequestPriority = .passive,
    irql_lock: hal.SpinLock = .{},
    dpc_queue: queue.PriorityQueue(dispatcher.Dpc, "hook", "priority", dispatcher.Dpc.Priority) = .{},
    dpc_lock: hal.SpinLock = .{},
    frame: ?*arch.SavedRegisterState = null,
};

pub var lcbs: []struct { a: LocalControlBlock align(4096) } = undefined;
const hal_smp = arch.smp.SmpUtil(LocalControlBlock);
pub const lcb = hal_smp.lcb;

fn init(page_alloc: std.mem.Allocator, gpa: std.mem.Allocator, wait_for_aps: bool) !void {
    lcb.syscall_stack = @ptrFromInt(@intFromPtr((try page_alloc.alignedAlloc(u8, 4096, 8192)).ptr) + 8192);

    lcb.idle_thread = try gpa.create(Thread);
    lcb.idle_thread.* = .{
        .header = .{
            .kind = .thread,
            .id = idle_thread_id,
        },
        .priority = .p1,
    };
    try lcb.idle_thread.setup_stack(page_alloc, @import("dispatcher/idle.zig").idle, null);
    if (wait_for_aps) {
        arch.smp.wait_for_all_aps();
        dispatcher.interrupts.enter_scheduling();
    }
}

pub fn allocate_lcbs(page_alloc: std.mem.Allocator, gpa: std.mem.Allocator) std.mem.Allocator.Error!void {
    lcbs = try page_alloc.alignedAlloc(std.meta.Elem(@TypeOf(lcbs)), 1 << 12, apic.processor_count);
    @memset(lcbs, .{ .a = .{} });
    set_lcb_base(@bitCast(@intFromPtr(&lcbs[apic.lapic_indices[apic.get_lapic_id()]].a)));
    try init(page_alloc, gpa, false);
    const t: *Thread = try gpa.create(Thread);
    t.* = .{
        .header = .{
            .kind = .thread,
            .id = zuid.new.v4(),
        },
        .priority = .p4,
    };

    t.stack = arch.smp.get_local_krnl_stack();
    lcb.current_thread = t;
    dispatcher.interrupts.enter_thread_ctx();
}

pub fn set_lcb_base(addr: isize) void {
    hal_smp.setup(addr);
}
