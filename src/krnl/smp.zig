const Thread = @import("thread/Thread.zig");
const dispatcher = @import("dispatcher/dispatcher.zig");
const hal = @import("hal/hal.zig");
const arch = hal.arch;
const apic = hal.apic;
const std = @import("std");
const collections = @import("collections");
const queue = collections.queue;
const zuid = @import("zuid");
const atomic = std.atomic;
const msr = arch.msr;

pub const idle_thread_id = zuid.UUID.nul;
pub const idle_client_thread_id = std.math.maxInt(u64) - 1;
const log = std.log.scoped(.smp);

pub const LocalControlBlock = struct {
    self: *LocalControlBlock,
    apic_id: u32,
    uid: u32,
    current_thread: ?*Thread = null,
    standby_thread: ?*Thread = null,
    idle_thread: *Thread = undefined,
    syscall_stack: usize = undefined,
    local_dispatcher_queue: LocalDispatcherQueueType = .{},
    local_dispatcher_lock: hal.SpinLock = .{},
    force_yield: bool = false,
    dpc_queue: DpcQueueType = .{},
    dpc_lock: hal.SpinLock = .{},
    frame: ?*arch.SavedRegisterState = null,
    arch_data: arch.smp.ArchPrcb = undefined,

    pub const LocalDispatcherQueueType = queue.PriorityQueue(Thread, "scheduler_hook", "priority", Thread.Priority);
    pub const DpcQueueType = queue.PriorityQueue(dispatcher.Dpc, "hook", "priority", dispatcher.Dpc.Priority);
};

pub const LcbWrapper = struct {
    lcb: LocalControlBlock align(4096),
    _pad: [std.mem.page_size - @sizeOf(LocalControlBlock)]u8 = undefined,
};

pub var lcbs: []LcbWrapper = undefined;
pub var smp_initialized: bool = false;
pub const lcb: *allowzero addrspace(.gs) const *LocalControlBlock = @ptrFromInt(@offsetOf(LcbWrapper, "lcb") + @offsetOf(LocalControlBlock, "self"));

fn init(page_alloc: std.mem.Allocator, gpa: std.mem.Allocator, wait_for_aps: bool) !void {
    dispatcher.WaitBlock.pool = dispatcher.WaitBlock.Pool.init(gpa);
    dispatcher.Dpc.pool = dispatcher.Dpc.Pool.init(gpa);

    const stack_slice = try page_alloc.alignedAlloc(u8, 4096, 8192);
    const stack_top = @intFromPtr(stack_slice.ptr) + 8192;
    const p: *LocalControlBlock = lcb.*;
    const base = arch.msr.read(.gs_base);
    log.debug("in smp init, block gs:0x0000000000000008->0x{x:0>16} (gs_base 0x{x:0>16}), stack at {*}", .{ @intFromPtr(lcb.*), base, stack_slice });
    // log.debug("NOTE: addr 0x0000000000000008 in flat addressing is 0x{x:0>16}", .{@as(*usize, @ptrFromInt(8)).*});
    p.syscall_stack = stack_top;

    p.idle_thread = try Thread.init(gpa, idle_thread_id, idle_client_thread_id);
    try p.idle_thread.setup_stack(page_alloc, @import("dispatcher/idle.zig").idle, null);
    if (wait_for_aps) {
        // arch.smp.wait_for_all_aps();
        dispatcher.interrupts.enter_scheduling();
    }
}

pub fn allocate_lcbs() !void {
    lcbs = try std.heap.page_allocator.alignedAlloc(LcbWrapper, 1 << 12, apic.lapics.len);
    const apic_ids = apic.lapics.items(.id);
    const uids = apic.lapics.items(.uid);
    for (lcbs, 0..) |*l, i| {
        l.* = .{
            .lcb = .{
                .self = &l.lcb,
                .apic_id = apic_ids[i],
                .uid = uids[i],
            },
        };
    }
}
pub fn enter_threading(page_alloc: std.mem.Allocator, gpa: std.mem.Allocator) !void {
    const id = apic.get_lapic_id();
    const idx = apic.lapic_indices[id];
    const base = @intFromPtr(&lcbs[idx]);
    log.debug("APIC {x}, idx {x}, base 0x{x:0>16}->0x{x:0>16}", .{ id, idx, base, base + @offsetOf(LcbWrapper, "lcb") });
    set_lcb_base(base);
    @atomicStore(bool, &smp_initialized, true, .seq_cst);
    try init(page_alloc, gpa, false);
    const is_bsp = id == apic.bspid;
    const t: *Thread = try Thread.init(gpa, if (is_bsp) zuid.UUID.max else zuid.UUID.new.v4(), if (is_bsp) 0 else std.crypto.random.intRangeAtMost(u64, 1, std.math.maxInt(u64) - 2));
    t.stack = arch.smp.get_local_krnl_stack();
    lcb.*.current_thread = t;
    dispatcher.interrupts.enter_thread_ctx();
}

pub fn set_lcb_base(addr: usize) void {
    msr.write(.gs_base, addr);
    msr.write(.kernel_gs_base, addr);
}
