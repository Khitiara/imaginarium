const dispatcher = @import("../dispatcher/dispatcher.zig");

header: dispatcher.DispatcherObject = .{ .kind = .semaphore },
available: usize,
spinlock: dispatcher.SpinLockIRQL = .{ .set_irql = .dispatch },

const Semaphore = @This();

pub fn init(count: usize) Semaphore {
    return .{ .available = count };
}
