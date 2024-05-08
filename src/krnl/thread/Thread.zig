const dispatcher = @import("../dispatcher/dispatcher.zig");
const ob = @import("../objects/ob.zig");
const util = @import("util");
const hal = @import("hal");
const arch = hal.arch;
const std = @import("std");
const queue = util.queue;

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

header: ob.Object,
lock: util.SpinLock = .{},
wait_list: queue.DoublyLinkedList(dispatcher.wait_block.WaitBlock, "thread_wait_list") = .{},
state: State = .init,
priority: Priority,
scheduler_hook: queue.Node = .{},
saved_state: SavedThreadState = undefined,
stack: []const u8 = undefined,

pub fn set_state(self: *@This(), expect: State, state: State) void {
    const old = @cmpxchgStrong(State, &self.State, expect, state, .acq_rel, .monotonic);
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
    // new RSP is the new top of stack
    // segment selectors set up for *KERNEL MODE*
    // flags copied from current flags EXCEPT the interrupt flag is set
    // new RCX is the address of the parameter (win64 callconv because rdi for first argument is dumb)
    // if the thread is to be a usermode thread, it is up to the kernel-mode thread start
    // to initialize necessary selectors, stack, etc to enter ring 0
    frame.rip = @intFromPtr(thread_start);
    frame.registers.rcx = @intFromPtr(param);
    self.stack = try allocator.alignedAlloc(u8, 1 << 12, 1 << 13);
    frame.rsp = @intFromPtr(self.stack) + self.stack.len;
    frame.eflags = arch.x86_64.flags();
    frame.eflags.interrupt_enable = true;
    frame.cs = arch.x86_64.gdt.selectors.kernel_code;
    frame.ss = arch.x86_64.gdt.selectors.kernel_data;
    frame.fs = arch.x86_64.gdt.selectors.kernel_data;
    frame.gs = arch.x86_64.gdt.selectors.kernel_data;
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    allocator.free(self.stack);
}
