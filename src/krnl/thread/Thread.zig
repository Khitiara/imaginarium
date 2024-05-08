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
state: State,
priority: Priority,
scheduler_hook: queue.Node,
saved_state: SavedThreadState,

pub fn set_state(self: *@This(), expect: State, state: State) void {
    const old = @cmpxchgStrong(State, &self.State, expect, state, .acq_rel, .monotonic);
    std.debug.assert(old != null);
}
