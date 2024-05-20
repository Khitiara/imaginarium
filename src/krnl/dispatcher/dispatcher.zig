const Thread = @import("../thread/Thread.zig");
const util = @import("util");
const queue = util.queue;

pub const interrupts = @import("interrupts.zig");
pub const scheduler = @import("scheduler.zig");
pub const Dpc = @import("Dpc.zig");
pub const SpinLockIRQL = @import("SpinLockIRQL.zig");

pub const WaitBlock = @import("WaitBlock.zig");

var global_dispatcher_lock: SpinLockIRQL = .{ .set_irql = .dispatch };
var dispatch_queue: queue.PriorityQueue(Thread, "scheduler_hook", "priority", Thread.Priority) = .{};

test {
    _ = interrupts.irql_map;
}
