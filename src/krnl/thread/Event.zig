const dispatcher = @import("../dispatcher/dispatcher.zig");
const Thread = @import("../thread/Thread.zig");
const smp = @import("../smp.zig");
const std = @import("std");
const hal = @import("../hal/hal.zig");
const InterruptRequestPriority = hal.InterruptRequestPriority;

const Event = @This();

spinlock: hal.QueuedSpinLock = .{},
wait_handle: dispatcher.WaitHandle = .{ .check_wait = &check_wait },
signalled: bool = false,
manual_reset: bool,

pub fn set(self: *Event, reset_irql: bool) bool {
    var token: hal.QueuedSpinLock.Token = .{};
    self.spinlock.lock(token);
    defer if (reset_irql) token.unlock() else token.unlock_unsafe();

    if (self.signalled) return;

    if (self.manual_reset) {
        self.wait_handle.release_all();
        self.signalled = true;
    } else if (!self.wait_handle.release_one()) {
        self.signalled = false;
    } else {
        self.signalled = true;
    }
}

pub fn reset(self: *Event) bool {
    var token: hal.QueuedSpinLock.Token = .{};
    self.spinlock.lock(token);
    defer token.unlock();

    const state = self.signalled;
    self.signalled = false;
    return state;
}

pub fn get_status(self: *Event) bool {
    var token: hal.QueuedSpinLock.Token = .{};
    self.spinlock.lock(token);
    defer token.unlock();

    return self.signalled;
}

fn check_wait(handle: *dispatcher.WaitHandle, thread: *Thread) !bool {
    const self: *Event = @fieldParentPtr("wait_handle", handle);
    var token: hal.QueuedSpinLock.Token = undefined;
    self.spinlock.lock(&token);
    defer token.unlock();
    // if manual_reset is false then this is an auto-reset event and we need to set signalled to false when satisfying
    // the wait. if manual_reset is true and signalled is already true then we need to leave signalled as true anyway.
    // therefore, a compare-exchange is a valid operation here.
    if (self.signalled) {
        self.signalled = self.manual_reset;
        return false;
    } else {
        try handle.enqueue_wait(thread);
        return true;
    }
}
