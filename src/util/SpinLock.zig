const hal = @import("hal");
const arch = hal.arch;
const std = @import("std");
const atomic = std.atomic;

serving: usize = 0,
allocated: usize = 0,

pub fn lock(self: *@This()) bool {
    const s = arch.get_and_disable_interrupts();
    self.lock_unsafe();
    return s;
}

pub fn lock_unsafe(self: *@This()) void {
    const ticket = @atomicRmw(usize, &self.allocated, .add, 1, .monotonic);
    while (true) {
        if(@atomicLoad(usize, &self.serving, .acquire) == ticket) {
            return;
        }
        arch.spin_hint();
    }
}

pub fn unlock(self: *@This(), saved_state: bool) void {
    self.unlock_unsafe();
    arch.restore_interrupt_state(saved_state);
}

pub fn unlock_unsafe(self: *@This()) void {
    _ = @atomicRmw(usize, &self.serving, .Add, 1, .Release);
}