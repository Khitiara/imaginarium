//! a reentrant spin-lock that also can use IRQL instead of needing to disable interrupts completely

const std = @import("std");
const atomic = std.atomic;
const hal = @import("root").hal;
const dispatcher = @import("dispatcher.zig");
const ints = dispatcher.interrupts;

key: u8 = 0,
irql: hal.InterruptRequestPriority = undefined,
set_irql: hal.InterruptRequestPriority,

pub fn lock(self: anytype) void {
    self.irql = ints.fetch_set_irql(self.set_irql, .raise);

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

    // while (self.key.bitSet(0, .acquire) == 1) {
    //     atomic.spinLoopHint();
    // }
}

pub fn unlock(self: anytype) void {
    _ = @atomicStore(u8, &self.key, 0, .release);
    ints.set_irql(self.irql, .lower);
}
