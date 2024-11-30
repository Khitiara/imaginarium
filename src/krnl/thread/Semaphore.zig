const dispatcher = @import("../dispatcher/dispatcher.zig");
const Thread = @import("../thread/Thread.zig");
const smp = @import("../smp.zig");
const InterruptRequestPriority = @import("../hal/hal.zig").InterruptRequestPriority;

const Semaphore = @This();

permits: usize,
spinlock: dispatcher.SpinLockIRQL = .{ .set_irql = .dispatch },
wait_handle: dispatcher.WaitHandle = .{ .check_wait = &check_wait },
decrement_dpc: ?*dispatcher.Dpc = null,

pub fn init(count: usize) Semaphore {
    return .{ .permits = count };
}

pub fn signal(self: *Semaphore) void {
    self.spinlock.lock(null);
    defer self.spinlock.unlock();
    self.permits += 1;
    if (@intFromEnum(smp.lcb.*.irql) > @intFromEnum(InterruptRequestPriority.dpc)) {
        if (self.decrement_dpc == null) {
            const dpc: *dispatcher.Dpc = dispatcher.Dpc.pool.create() catch @panic("Could not allocate DPC");
            self.decrement_dpc = dpc;
            dpc.* = .{
                .args = .{ self, null, null },
                .routine = &dec_dpc,
                .priority = .p2,
            };
            dispatcher.Dpc.schedule(dpc);
        }
    } else {
        self.decrement();
    }
}

pub fn reset(self: *Semaphore) void {
    self.spinlock.lock(null);
    defer self.spinlock.unlock();
    self.permits = 0;
}

fn dec_dpc(_: *const dispatcher.Dpc, self_opaque: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) void {
    const self: *Semaphore = @alignCast(@ptrCast(self_opaque.?));
    self.spinlock.lock(null);
    defer self.spinlock.unlock();
    self.decrement();
}

fn decrement(self: *Semaphore) void {
    while (self.permits > 0) : (self.permits -= 1) {
        if(!self.wait_handle.release_one()) break;
    }
}

fn check_wait(handle: *dispatcher.WaitHandle, thread: *Thread) !bool {
    const self: *Semaphore = @fieldParentPtr("wait_handle", handle);
    self.spinlock.lock(null);
    defer self.spinlock.unlock();
    if (self.permits > 0) {
        self.permits -= 1;
        return false;
    }

    try handle.enqueue_wait(thread);
    return true;
}
