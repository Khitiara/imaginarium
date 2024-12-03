const Thread = @import("../thread/Thread.zig");
const util = @import("util");
const queue = util.queue;

pub const interrupts = @import("interrupts.zig");
pub const scheduler = @import("scheduler.zig");
pub const Dpc = @import("Dpc.zig");
pub const SpinLock = @import("../hal/SpinLock.zig");

pub const WaitBlock = @import("WaitBlock.zig");
pub const WaitHandle = @import("WaitHandle.zig");

const smp = @import("../smp.zig");
const std = @import("std");
const assert = std.debug.assert;

var global_dispatcher_lock: SpinLock = .{};
var dispatch_queue: queue.PriorityQueue(Thread, "scheduler_hook", "priority", Thread.Priority) = .{};

pub fn yield() *Thread {
    smp.lcb.*.force_yield = true;
    interrupts.enter_scheduling();
}

pub inline fn wait_for_single_object(handle: WaitHandle) !void {
    try wait_for_multiple_objects(&.{handle}, .all);
}

pub fn wait_for_multiple_objects(targets: []*WaitHandle, mode: Thread.WaitType) !void {
    smp.lcb.*.local_dispatcher_lock.lock();
    defer smp.lcb.*.local_dispatcher_lock.unlock();
    if (@atomicRmw(?*Thread, &smp.lcb.*.current_thread, .Xchg, null, .acq_rel)) |thread| {
        thread.wait_lock.lock();
        defer thread.wait_lock.unlock();
        var wait_needed: bool = false;

        thread.set_state(.running, .blocked);
        thread.wait_type = mode;
        for (targets) |wait_handle| {
            wait_handle.wait_lock.lock();
            defer wait_handle.wait_lock.unlock();

            if (try wait_handle.check_wait(thread)) {
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
