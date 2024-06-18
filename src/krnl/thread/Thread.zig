const dispatcher = @import("../dispatcher/dispatcher.zig");
const ob = @import("../objects/ob.zig");
const util = @import("util");
const hal = @import("../hal/hal.zig");
const arch = hal.arch;
const std = @import("std");
const queue = util.queue;
const smp = @import("../smp.zig");
const zuid = @import("zuid");
const atomic = std.atomic;

pub const Semaphore = @import("Semaphore.zig");

pub const State = enum {
    /// being initialized
    init,
    /// ready to run, pending reaching the front of the queue for some processor
    ready,
    /// assigned to a processor pending the processor-local lock
    assigned,
    /// assigned to a processor and next in line to run there
    standby,
    /// currently running on a processor
    running,
    /// waiting on one or more objects
    blocked,
    /// kernel-mode stack currently swapped out of memory
    pages_pending,
    /// pending object deletion
    terminated,
};

pub const Priority = util.PriorityEnum(8);

pub const SavedThreadState = struct {
    registers: arch.SavedRegisterState,
};

pub const WaitType = enum {
    await_ny,
    all,
};

pub const Affinity = struct {
    last_processor: u8 = 0xFF,
    want_processor: union(enum) {
        no_pref: void,
        processor: u8,
        core: u8,
        chip: u8,
    } = .no_pref,
};

header: ob.Object,
wait_lock: dispatcher.SpinLockIRQL = .{ .set_irql = .dispatch },
wait_type: WaitType = undefined,
wait_list: WaitListType = .{},
join: dispatcher.WaitHandle = .{},
state: State = .init,
priority: Priority,
affinity: Affinity = .{},
scheduler_hook: queue.Node = .{},
saved_state: SavedThreadState = undefined,
stack: ?[]const u8 = null,
tls: []const u8,
tls_ptr: usize,

const WaitListType = queue.DoublyLinkedList(dispatcher.WaitBlock, "thread_wait_list");

pub fn init2(alloc: std.mem.Allocator, tls_block: []u8, tls_ptr: usize, id: zuid.UUID) !*@This() {
    const self = try alloc.create(@This());
    self.* = .{
        .header = .{
            .kind = .thread,
            .id = id,
        },
        .priority = .p1,
        .tls = tls_block,
        .tls_ptr = tls_ptr,
    };
    if(smp.krnl_tls_len > 0) {
        @memset(tls_block, 0);
        @memcpy(tls_block[tls_block.len - smp.krnl_tls_len - 8 ..][0..smp.initial_tls.len], smp.initial_tls);
        @as(*align(1) *u8, @ptrCast(&tls_block[smp.krnl_tls_len])).* = &tls_block[smp.krnl_tls_len];
    }
    return self;
}

pub fn init(alloc: std.mem.Allocator, id: zuid.UUID) !*@This() {
    const tls = try alloc.alignedAlloc(u8, 1 << 12, smp.krnl_tls_len + 8);
    return try init2(alloc, tls, @intFromPtr(&tls[smp.krnl_tls_len]), id);
}

pub fn set_state(self: *@This(), expect: State, state: State) void {
    const old = @cmpxchgStrong(State, &self.state, expect, state, .acq_rel, .monotonic);
    std.debug.assert(old != null);
}

pub fn setup_stack(self: *@This(), allocator: std.mem.Allocator, thread_start: *const fn (*anyopaque) callconv(.Win64) noreturn, param: ?*anyopaque) !void {
    // note the noreturn on the thread_start - the thread_start must only exit by
    // removing this thread from the LCB and using a (spoofed) interrupt to enter
    // the main dispatcher next thread selection, which will switch to a new thread.
    // note that a thread can just not exit, as is the case with the idle thread
    // which loops infinitely for as long as the system stays online.

    const frame = &self.saved_state.registers;
    @memset(std.mem.asBytes(frame), 0);
    // all normally-saved registers are 0 EXCEPT:
    // new RIP is the thread start
    // new RSP is the new top of stack - 2 usizes
    // top two usizes of the stack are cleared to 0
    // segment selectors set up for *KERNEL MODE*
    // flags copied from current flags EXCEPT the interrupt flag is set
    // new RCX is the address of the parameter (win64 callconv because rdi for first argument is dumb)
    // if the thread is to be a usermode thread, it is up to the kernel-mode thread start
    // to initialize necessary selectors, stack, etc to enter ring 0
    frame.rip = @intFromPtr(thread_start);
    frame.registers.rcx = @intFromPtr(param);
    const stk = try allocator.alignedAlloc(u8, 1 << 12, 1 << 12);
    self.stack = stk;
    @memset(@constCast(stk[stk.len - (3 * @sizeOf(usize)) ..]), 0);
    frame.rsp = @intFromPtr(stk.ptr) + stk.len;
    frame.rsp -= 2 * @sizeOf(usize);
    frame.eflags = arch.x86_64.flags();
    frame.eflags.interrupt_enable = true;
    frame.cs = arch.x86_64.gdt.selectors.kernel_code;
    frame.ss = arch.x86_64.gdt.selectors.kernel_data;
    frame.fs = arch.x86_64.gdt.selectors.kernel_data;
    frame.gs = arch.x86_64.gdt.selectors.kernel_data;
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    if (self.stack) |stk| {
        allocator.free(stk);
        self.stack = null;
    }
    allocator.free(self.tls);
}
