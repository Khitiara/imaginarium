const Thread = @import("../thread/Thread.zig");
const util = @import("util");
const queue = util.queue;

pub const interrupts = @import("interrupts.zig");
pub const scheduler = @import("scheduler.zig");
pub const Dpc = @import("Dpc.zig");
pub const QueuedSpinLock = @import("../hal/QueuedSpinLock.zig");

pub const WaitBlock = @import("WaitBlock.zig");
pub const WaitHandle = @import("WaitHandle.zig");

const smp = @import("../smp.zig");
const std = @import("std");
const assert = std.debug.assert;

var global_dispatcher_lock: QueuedSpinLock = .{};
var dispatch_queue: queue.PriorityQueue(Thread, "scheduler_hook", "priority", Thread.Priority) = .{};

pub fn yield() *Thread {
    smp.lcb.*.force_yield = true;
    interrupts.enter_scheduling();
}

pub inline fn wait_for_single_object(handle: *WaitHandle) !void {
    try wait_for_multiple_objects(&.{handle}, .all);
}

pub fn wait_for_multiple_objects(targets: []const *WaitHandle, mode: Thread.WaitType) !void {
    const irql = smp.lcb.*.local_dispatcher_lock.lock();
    defer smp.lcb.*.local_dispatcher_lock.unlock(irql);
    if (@atomicRmw(?*Thread, &smp.lcb.*.current_thread, .Xchg, null, .acq_rel)) |thread| {
        var tok: QueuedSpinLock.Token = undefined;
        thread.wait_lock.lock(&tok);
        defer tok.unlock();
        var wait_needed: bool = false;

        thread.set_state(.running, .blocked);
        thread.wait_type = mode;
        for (targets) |wait_handle| {
            var tok2: QueuedSpinLock.Token = undefined;
            wait_handle.wait_lock.lock(&tok2);
            defer tok2.unlock();

            if (try wait_handle.check_wait(wait_handle, thread)) {
                wait_needed = true;
            }
        }
        if (!wait_needed) {
            smp.lcb.*.current_thread = thread;
        }
    } else {
        @panic("Wait with no thread current");
    }
}
