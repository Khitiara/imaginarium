const hal = @import("hal");
const arch = hal.arch;

pub fn idle(_: ?*anyopaque) noreturn {
    while (true) {
        arch.delay_unsafe(100);
        arch.disable_interrupts();
        arch.enable_interrupts();
    }
}
