const dispatcher = @import("../dispatcher/dispatcher.zig");
const Thread = @import("../thread/Thread.zig");
const smp = @import("../smp.zig");
const InterruptRequestPriority = @import("../hal/hal.zig").InterruptRequestPriority;
const std = @import("std");

const Mutex = @This();

spinlock: @import("../hal/SpinLock.zig") = .{},
wait_handle: dispatcher.WaitHandle = .{ .check_wait = &check_wait },
held: ?u64 = null,
reentrant: bool = false,

fn check_wait(handle: *dispatcher.WaitHandle, thread: *Thread) !bool {
    const self: *Mutex = @fieldParentPtr("wait_handle", handle);
    const irql = self.spinlock.lock();
    defer self.spinlock.unlock(irql);
    if (self.held) |h| if (!self.reentrant or h != thread.client_ids.threadid) {
        try handle.enqueue_wait(thread);
        return true;
    };
    self.held = thread.client_ids.threadid;
    return false;
}

pub fn release(self: *Mutex) void {
    const irql = self.spinlock.lock();
    defer self.spinlock.unlock(irql);
    const tid = smp.lcb.*.current_thread.?.client_ids.threadid;
    std.debug.assert(tid == self.held);
    self.held = null;
}