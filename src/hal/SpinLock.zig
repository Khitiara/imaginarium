//! a simple spin-lock for small fast blocks. for this spinlock to function properly, interrupts may not fire
//! while the lock is held. for this reason, this spinlock should be held for as short a period as possible
//! while still ensuring correct behavior for the locked section

const arch = @import("arch/arch.zig");
const std = @import("std");
const atomic = std.atomic;

serving: usize = 0,
allocated: usize = 0,

/// acquire the spinlock. this version of the method disables interrupts before entering the loop,
/// returning the previous interrupt flag
pub fn lock(self: anytype) bool {
    const s = arch.get_and_disable_interrupts();
    self.lock_unsafe();
    return s;
}

/// acquire the spinlock. this version of the method leaves the interrupt flag as it is, and may be broken
/// if an interrupt fires while in the acquire loop
pub fn lock_unsafe(self: anytype) void {
    const ticket = @atomicRmw(usize, &self.allocated, .Add, 1, .monotonic);
    while (true) {
        if (@atomicLoad(usize, &self.serving, .acquire) == ticket) {
            return;
        }
        arch.spin_hint();
    }
}

/// release the spinlock, restoring the interrupt flag to the state saved when the spinlock was acquired
pub fn unlock(self: anytype, saved_state: bool) void {
    self.unlock_unsafe();
    arch.restore_interrupt_state(saved_state);
}

/// release the spinlock, leaving the interrupt flag as is
pub fn unlock_unsafe(self: anytype) void {
    _ = @atomicRmw(usize, &self.serving, .Add, 1, .release);
}
