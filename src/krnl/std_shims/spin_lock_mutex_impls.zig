const hal = @import("../hal/hal.zig");
const SpinLock = hal.SpinLock;

pub const HighSpinLockMutex = struct {
    spin_lock: SpinLock = .{},
    saved_state: bool = false,

    pub fn lock(self: *HighSpinLockMutex) void {
        self.saved_state = self.spin_lock.lock_cli();
    }

    pub fn unlock(self: *HighSpinLockMutex) void {
        self.spin_lock.unlock_sti(self.saved_state);
    }
};