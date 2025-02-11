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
const io = @import("io/io.zig");

pub const idle_thread_id = zuid.UUID.nul;
const log = std.log.scoped(.smp);

pub const ProcInfo = struct {
    apic_id: u32,
    uid: u32,
    boot_info_index: usize = 0,
    lapic_index: usize = 0,
};

pub const LocalControlBlock = struct {
    self: *LocalControlBlock,
    info: ProcInfo,
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
    processor_device: ?*io.Device = null,

    pub const LocalDispatcherQueueType = queue.PriorityQueue(Thread, "scheduler_hook", "priority", Thread.Priority);
    pub const DpcQueueType = queue.PriorityQueue(dispatcher.Dpc, "hook", "priority", dispatcher.Dpc.Priority);
};

pub const LcbWrapper = struct {
    lcb: LocalControlBlock align(4096),
    _pad: [std.heap.pageSize() - @sizeOf(LocalControlBlock)]u8 = undefined,
};

pub var prcbs: [*]LcbWrapper = @import("hal/mm/map.zig").prcbs;

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

    p.idle_thread = try Thread.init(gpa, idle_thread_id);
    try p.idle_thread.setup_stack(page_alloc, @import("dispatcher/idle.zig").idle, null);
    if (wait_for_aps) {
        // arch.smp.wait_for_all_aps();
        dispatcher.interrupts.enter_scheduling();
    }
}

const boot = @import("boot/boot_info.zig");

pub fn enter_threading(page_alloc: std.mem.Allocator, gpa: std.mem.Allocator) !void {
    const id = apic.get_lapic_id();
    const base = @intFromPtr(&prcbs[id]);
    log.debug("APIC {x}, base 0x{x:0>16}->0x{x:0>16}", .{ id, base, base + @offsetOf(LcbWrapper, "lcb") });
    set_lcb_base(base);
    try init(page_alloc, gpa, false);
    const t: *Thread = try Thread.init(gpa, zuid.UUID.new.v4());
    t.stack = arch.smp.get_local_krnl_stack();
    lcb.*.current_thread = t;
    dispatcher.interrupts.enter_thread_ctx();
}

pub fn set_lcb_base(addr: usize) void {
    msr.write(.gs_base, addr);
    msr.write(.kernel_gs_base, addr);
}
