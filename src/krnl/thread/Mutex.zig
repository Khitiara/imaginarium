const dispatcher = @import("../dispatcher/dispatcher.zig");
const Thread = @import("../thread/Thread.zig");
const smp = @import("../smp.zig");
const InterruptRequestPriority = @import("../hal/hal.zig").InterruptRequestPriority;
const std = @import("std");
const builtin = @import("builtin");
const QueuedSpinlock = @import("../hal/QueuedSpinLock.zig");

const Mutex = @This();

spinlock: @import("../hal/hal.zig").SpinLock = .{},
wait_handle: dispatcher.WaitHandle = .{ .check_wait = &check_wait },
state: std.atomic.Value(u32) = std.atomic.Value(u32).init(unlocked),

const unlocked: u32 = 0b00;
const locked: u32 = 0b01;

pub fn tryLock(self: *Mutex) bool {
    if (comptime builtin.target.cpu.arch.isX86()) {
        const locked_bit = comptime @ctz(locked);
        return self.state.bitSet(locked_bit, .acquire) == 0;
    }
    return self.state.cmpxchgWeak(unlocked, locked, .acquire, .monotonic) == null;
}

fn check_wait(handle: *dispatcher.WaitHandle, thread: *Thread) !bool {
    const self: *Mutex = @fieldParentPtr("wait_handle", handle);
    if (!self.tryLock()) {
        try handle.enqueue_wait(thread);
        return true;
    }
    return false;
}

pub fn release(self: *Mutex) void {
    var tok: QueuedSpinlock.Token = undefined;
    self.wait_handle.wait_lock.lock(&tok);
    defer tok.unlock();
    if(!self.wait_handle.release_one()) {
        self.state.store(unlocked, .release);
    }
}
