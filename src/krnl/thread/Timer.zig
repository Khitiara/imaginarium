const dispatcher = @import("../dispatcher/dispatcher.zig");
const Thread = @import("../thread/Thread.zig");
const smp = @import("../smp.zig");
const hal = @import("../hal/hal.zig");
const InterruptRequestPriority = hal.InterruptRequestPriority;
const std = @import("std");

const Timer = @This();
spinlock: hal.SpinLock = .{},
wait_handle: dispatcher.WaitHandle = .{ .check_wait = &check_wait },
due_time: u64,
period: ?u64,

fn check_wait(handle: *dispatcher.WaitHandle, thread: *Thread) !bool {
    const self: *Timer = @fieldParentPtr("wait_handle", handle);
    const irql = self.spinlock.lock();
    defer self.spinlock.unlock(irql);
    _ = thread;
    return false;
}