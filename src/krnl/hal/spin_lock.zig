//! a simple spin-lock for small fast blocks. for this spinlock to function properly, interrupts may not fire
//! while the lock is held. for this reason, this spinlock should be held for as short a period as possible
//! while still ensuring correct behavior for the locked section

const std = @import("std");
const hal = @import("hal.zig");
const atomic = std.atomic;

pub const SpinLock = extern struct {
    key: atomic.Value(usize) = .init(0),

    /// acquire the spinlock. this version of the method raises the IRQL before entering the loop
    pub fn lock(self: *SpinLock) hal.InterruptRequestPriority {
        return self.lock_at(.dispatch);
    }

    pub fn lock_at(self: *SpinLock, i: hal.InterruptRequestPriority) hal.InterruptRequestPriority {
        const irql = hal.get_irql();
        hal.raise_irql(i);
        self.lock_unsafe();
        return irql;
    }

    pub fn lock_cli(self: *SpinLock) bool {
        const int = hal.arch.idt.get_and_disable().interrupt_enable;
        self.lock_unsafe();
        return int;
    }

    /// acquire the spinlock. this version of the method leaves the interrupt flag as it is, and may be broken
    /// if an interrupt fires while in the acquire loop
    pub fn lock_unsafe(self: *SpinLock) void {
        asm volatile (
            \\  1:  lock bts $0, %[key]
            \\      jc 2f
            \\      jmp 3f
            \\  2:  pause
            \\      bt $0, %[key]
            \\      jnc 2b
            \\      jmp 1b
            \\  3:
            :
            : [key] "*p" (&self.key.raw),
            : "ss", "memory"
        );
    }

    /// release the spinlock, restoring the interrupt flag to the state saved when the spinlock was acquired
    pub fn unlock(self: *SpinLock, irql: hal.InterruptRequestPriority) void {
        self.unlock_unsafe();
        hal.lower_irql(irql);
    }

    /// release the spinlock, leaving the interrupt flag as is
    pub fn unlock_unsafe(self: *SpinLock) void {
        _ = self.key.bitReset(0, .release);
    }

    pub fn unlock_sti(self: *SpinLock, saved_interrupt_flag: bool) void {
        self.unlock_unsafe();
        if(saved_interrupt_flag) hal.arch.idt.enable();
    }
};

