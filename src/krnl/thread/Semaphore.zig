const dispatcher = @import("../dispatcher/dispatcher.zig");
const ob = @import("../objects/ob.zig");

header: ob.Object = .{ .kind = .semaphore },
permits: usize,
spinlock: dispatcher.SpinLockIRQL = .{ .set_irql = .dispatch },

const Semaphore = @This();

pub fn init(count: usize) Semaphore {
    return .{ .permits = count };
}
