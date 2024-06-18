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