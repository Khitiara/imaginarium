const Thread = @import("../thread/Thread.zig");
const util = @import("util");
const queue = util.queue;

pub const interrupts = @import("interrupts.zig");
pub const scheduler = @import("scheduler.zig");
pub const Dpc = @import("Dpc.zig");

pub const InterruptRequestPriority = enum(u4) {
    passive = 0x0,
    dispatch = 0x2,
    dpc = 0x3,
    dev_0 = 0x4,
    dev_1 = 0x5,
    dev_2 = 0x6,
    dev_3 = 0x7,
    dev_4 = 0x8,
    dev_5 = 0x9,
    dev_6 = 0xA,
    dev_7 = 0xB,
    sync = 0xC,
    clock = 0xD,
    ipi = 0xE,
    high = 0xF,
    /// exclude IRQL 1 because we cant make actual vectors with that priority
    _,

    pub fn lower(self: InterruptRequestPriority) InterruptRequestPriority {
        if (self == .passive or self == .dispatch)
            return .passive;
        return @enumFromInt(@intFromEnum(self) - 1);
    }
    pub fn raise(self: InterruptRequestPriority) InterruptRequestPriority {
        if (self == .passive)
            return .dispatch;
        return @enumFromInt(@intFromEnum(self) +| 1);
    }
};

pub const WaitBlock = @import("WaitBlock.zig");

var global_dispatcher_lock: util.SpinLock = .{};
var dispatch_queue: queue.PriorityQueue(Thread, "scheduler_hook", "priority", Thread.Priority) = .{};

test {
    _ = interrupts.irql_map;
}
