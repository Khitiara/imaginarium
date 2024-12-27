const dispatcher = @import("../dispatcher/dispatcher.zig");
const Thread = @import("../thread/Thread.zig");
const smp = @import("../smp.zig");
const InterruptRequestPriority = @import("../hal/hal.zig").InterruptRequestPriority;
const hal = @import("../hal/hal.zig");

const Semaphore = @This();

permits: usize,
spinlock: @import("../hal/SpinLock.zig") = .{},
wait_handle: dispatcher.WaitHandle = .{ .check_wait = &check_wait },
decrement_dpc: ?*dispatcher.Dpc = null,

pub fn init(count: usize) Semaphore {
    return .{ .permits = count };
}

pub fn signal(self: *Semaphore) void {
    var tok: hal.QueuedSpinLock.Token = undefined;
    self.wait_handle.wait_lock.lock(&tok);
    defer tok.unlock();
    self.permits += 1;
    if (@intFromEnum(hal.get_irql()) > @intFromEnum(InterruptRequestPriority.dispatch)) {
        if (self.decrement_dpc == null) {
            self.decrement_dpc = dispatcher.Dpc.init_and_schedule(.p2, &dec_dpc, .{ self, null, null }) catch @panic("Could not allocate DPC");
        }
    } else {
        self.decrement();
    }
}

pub fn reset(self: *Semaphore) void {
    const irql = self.spinlock.lock();
    defer self.spinlock.unlock(irql);
    self.permits = 0;
}

fn dec_dpc(dpc: *dispatcher.Dpc, self: *Semaphore, _: ?*anyopaque, _: ?*anyopaque) void {
    const irql = self.spinlock.lock();
    defer self.spinlock.unlock(irql);
    self.decrement();
    dpc.deinit();
    self.decrement_dpc = null;
}

fn decrement(self: *Semaphore) void {
    while (self.permits > 0) : (self.permits -= 1) {
        if (!self.wait_handle.release_one()) break;
    }
}

pub fn try_wait(self: *Semaphore) bool {
    const irql = self.spinlock.lock();
    defer self.spinlock.unlock(irql);

    if (self.permits > 0) {
        self.permits -= 1;
        return true;
    }
    return true;
}

fn check_wait(handle: *dispatcher.WaitHandle, thread: *Thread) !bool {
    const self: *Semaphore = @fieldParentPtr("wait_handle", handle);
    const irql = self.spinlock.lock();
    defer self.spinlock.unlock(irql);
    if (self.permits > 0) {
        self.permits -= 1;
        return false;
    }

    try handle.enqueue_wait(thread);
    return true;
}
