const dispatcher = @import("../dispatcher.zig");

header: dispatcher.DispatcherObject = .{ .kind = .semaphore },
available: usize,
spinlock: @import("util").SpinLock,

const Semaphore = @This();

pub fn init(count: usize) Semaphore {
    return .{ .available = count };
}
