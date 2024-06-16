const hal = @import("../hal/hal.zig");
const arch = hal.arch;
const interrupts = @import("interrupts.zig");

pub fn idle(_: ?*anyopaque) callconv(.Win64) noreturn {
    while (true) {
        arch.delay_unsafe(100);
        interrupts.enter_scheduling();
    }
}

test {
    _ = idle;
}
