const Thread = @import("thread/Thread.zig");
const dispatcher = @import("dispatcher/dispatcher.zig");
const hal = @import("hal/hal.zig");
const arch = hal.arch;
const apic = hal.apic;
const std = @import("std");
const util = @import("util");
const queue = util.queue;
const zuid = @import("zuid");
const atomic = std.atomic;

pub const idle_thread_id = zuid.UUID.nul;
const log = std.log.scoped(.smp);

pub const LocalControlBlock = struct {
    self: *LocalControlBlock,
    apic_id: u8,
    current_thread: ?*Thread = null,
    standby_thread: ?*Thread = null,
    idle_thread: *Thread = undefined,
    syscall_stack: usize = undefined,
    local_dispatcher_queue: queue.PriorityQueue(Thread, "scheduler_hook", "priority", Thread.Priority) = .{},
    local_dispatcher_lock: dispatcher.SpinLockIRQL = .{ .set_irql = .dispatch },
    force_yield: bool = false,
    irql: hal.InterruptRequestPriority = .passive,
    dpc_queue: queue.PriorityQueue(dispatcher.Dpc, "hook", "priority", dispatcher.Dpc.Priority) = .{},
    dpc_lock: dispatcher.SpinLockIRQL = .{ .set_irql = .dpc },
    frame: ?*arch.SavedRegisterState = null,
};

const LcbWrapper = struct {
    lcb: LocalControlBlock align(4096),
};

pub var lcbs: []LcbWrapper = undefined;
const hal_smp = arch.smp.SmpUtil(LcbWrapper, LocalControlBlock, &.{ "lcb", "self" });
pub const lcb = hal_smp.lcb;

pub var krnl_tls_len: usize = undefined;

fn init(page_alloc: std.mem.Allocator, gpa: std.mem.Allocator, wait_for_aps: bool) !void {
    dispatcher.WaitBlock.pool = dispatcher.WaitBlock.Pool.init(gpa);
    dispatcher.Dpc.pool = dispatcher.Dpc.Pool.init(gpa);

    const stack_slice = try page_alloc.alignedAlloc(u8, 4096, 8192);
    const stack_top = @intFromPtr(stack_slice.ptr) + 8192;
    const p: *LocalControlBlock = lcb.*;
    const base = arch.x86_64.msr.read(.gs_base);
    log.debug("in smp init, block gs:0x0000000000000008->0x{x:0>16} (gs_base 0x{x:0>16}), stack at {*}", .{ @intFromPtr(lcb.*), base, stack_slice });
    log.debug("NOTE: addr 0x0000000000000008 in flat addressing is 0x{x:0>16}", .{@as(*usize, @ptrFromInt(8)).*});
    p.syscall_stack = stack_top;

    p.idle_thread = try Thread.init(gpa, idle_thread_id);
    try p.idle_thread.setup_stack(page_alloc, @import("dispatcher/idle.zig").idle, null);
    if (wait_for_aps) {
        arch.smp.wait_for_all_aps();
        dispatcher.interrupts.enter_scheduling();
    }
}

pub fn set_tls_base(thread: *const Thread) void {
    hal_smp.set_tls(thread.tls_ptr);
}

pub var initial_tls: []const u8 = undefined;

pub fn allocate_lcbs(page_alloc: std.mem.Allocator, gpa: std.mem.Allocator) !void {
    try @import("own_elf.zig").get_tls_size(&krnl_tls_len, &initial_tls);

    lcbs = try page_alloc.alignedAlloc(LcbWrapper, 1 << 12, apic.lapics.len);
    for (lcbs, 0..) |*l, i| {
        l.* = .{
            .lcb = .{
                .self = &l.lcb,
                .apic_id = apic.lapics.items(.id)[i],
            },
        };
        // @memset(l.lcb.tls_block, 0);
        // @memcpy(l.lcb.tls_block, initial_bit);
    }

    const id = apic.get_lapic_id();
    const idx = apic.lapic_indices[id];
    const base = @intFromPtr(&lcbs[idx]);
    log.debug("APIC {x}, idx {x}, base 0x{x:0>16}->0x{x:0>16}", .{ id, idx, base, base + @offsetOf(LcbWrapper, "lcb") });
    set_lcb_base(base);
    try init(page_alloc, gpa, false);
    const tls: []u8, const tls_ptr = if (krnl_tls_len > 0) blk: {
        const t = try gpa.alloc(u8, krnl_tls_len + 8);
        const tp = @intFromPtr(&t[krnl_tls_len]);
        hal_smp.set_tls(tp);
        break :blk .{ t, tp };
    } else .{ &.{}, 0 };
    // try @import("debug.zig").dump_hex(tls);
    const t: *Thread = try Thread.init2(gpa, tls, tls_ptr, zuid.UUID.new.v4());
    t.stack = arch.smp.get_local_krnl_stack();
    lcb.*.current_thread = t;
    dispatcher.interrupts.enter_thread_ctx();
}

pub fn set_lcb_base(addr: usize) void {
    hal_smp.setup(addr);
}
