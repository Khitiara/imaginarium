//! a simple spin-lock for small fast blocks. for this spinlock to function properly, interrupts may not fire
//! while the lock is held. for this reason, this spinlock should be held for as short a period as possible
//! while still ensuring correct behavior for the locked section

const std = @import("std");
const hal = @import("hal.zig");
const atomic = std.atomic;

const SpinLock = @This();

key: usize = 0,

/// acquire the spinlock. this version of the method raises the IRQL before entering the loop
pub fn lock(self: *SpinLock) hal.InterruptRequestPriority {
    return self.lock_at(.dispatch);
}

pub fn lock_at(self: *SpinLock, i: hal.InterruptRequestPriority) hal.InterruptRequestPriority {
    const irql = hal.fetch_set_irql(i, .raise);
    self.lock_unsafe();
    return irql;
}

/// acquire the spinlock. this version of the method leaves the interrupt flag as it is, and may be broken
/// if an interrupt fires while in the acquire loop
pub fn lock_unsafe(self: *SpinLock) void {
    asm volatile (
        \\  1:  lock bts $0, %[key]
        \\      jnc 3f
        \\  2:  pause
        \\      testb $1, %[key]
        \\      jnz 2b
        \\      jmp 1b
        \\  3:
        :
    : [key] "*p" (&self.key),
    : "ss", "memory"
    );
}

/// release the spinlock, restoring the interrupt flag to the state saved when the spinlock was acquired
pub fn unlock(self: *SpinLock, irql: hal.InterruptRequestPriority) void {
    self.unlock_unsafe();
    _ = hal.set_irql(irql, .lower);
}

/// release the spinlock, leaving the interrupt flag as is
pub fn unlock_unsafe(self: *SpinLock) void {
    _ = @atomicStore(usize, &self.key, 0, .release);
}
