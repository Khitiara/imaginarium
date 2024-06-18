const Thread = @import("../thread/Thread.zig");
const util = @import("util");
const queue = util.queue;

pub const interrupts = @import("interrupts.zig");
pub const scheduler = @import("scheduler.zig");
pub const Dpc = @import("Dpc.zig");
pub const SpinLockIRQL = @import("SpinLockIRQL.zig");

pub const WaitBlock = @import("WaitBlock.zig");
pub const WaitHandle = @import("WaitHandle.zig");

const smp = @import("../smp.zig");
const std = @import("std");
const assert = std.debug.assert;

var global_dispatcher_lock: SpinLockIRQL = .{ .set_irql = .dispatch };
var dispatch_queue: queue.PriorityQueue(Thread, "scheduler_hook", "priority", Thread.Priority) = .{};

pub fn yield() *Thread {
    smp.lcb.*.force_yield = true;
    interrupts.enter_scheduling();
}

pub inline fn wait_for_single_object(handle: WaitHandle) !void {
    try wait_for_multiple_objects(&.{handle}, .all);
}

pub fn wait_for_multiple_objects(targets: []*WaitHandle, mode: Thread.WaitType) !void {
    if (@atomicRmw(?*Thread, &smp.lcb.*.current_thread, .Xchg, null, .acq_rel)) |thread| {
        thread.lock.lock();
        defer thread.lock.unlock();

        thread.set_state(.running, .blocked);
        thread.wait_type = mode;
        for (targets) |wait_handle| {
            wait_handle.wait_lock.lock();
            defer wait_handle.wait_lock.unlock();

            const block: *WaitBlock = try WaitBlock.pool.create();
            block.thread = thread;
            block.target = wait_handle;
            wait_handle.wait_queue.add_back(block);
            thread.wait_list.add_back(block);
        }
    } else {
        @panic("Wait with no thread current");
    }
}

