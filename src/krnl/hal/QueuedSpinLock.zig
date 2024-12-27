const std = @import("std");
const hal = @import("hal.zig");

const QueuedSpinLock = @This();

pub const Token = struct {
    /// a pointer to the lock. since this is aligned to 8 bytes, we use bit 1 as the wait flag
    lock: *QueuedSpinLock,
    /// the next token in the queue, if one exists
    next: ?*Token,
    /// the saved irql to restore on unlock
    saved_irql: hal.InterruptRequestPriority,

    pub fn unlock(token: *Token) void {
        unlock_unsafe(token);
        _ = hal.lower_irql(token.saved_irql);
    }

    pub fn unlock_unsafe(token: *Token) void {
        // quick load of the next in line
        var next = @atomicLoad(?*Token, &token.next, .acquire);
        if (next == null) {
            // if noone else is in line, then we are the tail.
            // thus, do a compare-exchange to null out the lock's
            // entry pointer atomically.
            const l: *QueuedSpinLock = @ptrFromInt(@intFromPtr(token.lock) & (~@as(usize, 1)));
            if (@cmpxchgStrong(?*Token, &l.entry, token, null, .release, .monotonic) == null) {
                // the compare-exchange succeeded, which means that the atomicRmw in lock_unsafe
                // was not executed since the atomicLoad above (ergo our free occurs BEFORE a queue-join).
                // therefore, the lock is properly freed and we can just return
                return;
            }

            // the compare-exchange failed. therefore, someone else has
            // joined the queue. we want to free the head, so wait for our
            // next pointer to be set
            while (next == null) {
                asm volatile ("pause");
                next = @atomicLoad(?*Token, &token.next, .acquire);
            }
        }
        // since our next should only be set after the next's wait flag is set,
        // and the only way to unset the flag should be this function,
        // the next token's wait flag should thus always be set here.
        std.debug.assert(@as(*u64, @ptrCast(&next.?.lock)).* & 1 != 0);

        // since the next token's wait flag is guaranteed set here, an xor is
        // a quick and easy way to atomically unset the flag
        _ = @atomicRmw(u64, @as(*u64, @ptrCast(&next.?.lock)), .Xor, 1, .acq_rel);
    }
};

/// the TAIL of the wait queue, if anyone is waiting.
/// the current holder of the lock maintains a reference to the head of the queue
/// which doubles as its token of ownership of the lock
entry: ?*Token = null,

pub fn lock(self: *QueuedSpinLock, token: *Token) void {
    self.lock_at(token, .dispatch);
}

pub fn lock_at(self: *QueuedSpinLock, token: *Token, tgt: hal.InterruptRequestPriority) void {
    const irql = hal.get_irql();
    hal.raise_irql(tgt);
    self.lock_unsafe(token);
    token.saved_irql = irql;
}

pub fn lock_unsafe(self: *QueuedSpinLock, token: *Token) void {
    // I dont trust RLS enough to just return this while still using a pointer to it
    // so we take a pointer and assign over the contents instead
    token.* = .{
        .lock = self,
        .next = null,
        .saved_irql = .passive,
    };
    // atomically exchange ourself into the lock's tail pointer.
    if (@atomicRmw(?*Token, &self.entry, .Xchg, token, .acq_rel)) |tail| {
        // there's an old tail, which means theres an old head, which means the lock is taken

        // set the wait flag before append so we can get freed immediately
        _ = @atomicRmw(u64, @as(*u64, @ptrCast(&token.lock)), .Or, 1, .release);
        // and append ourself on the queue
        @atomicStore(?*Token, &tail.next, token, .release);

        // do..while loop until the wait flag is unset.
        // when the lock is freed by the current holder
        // they will unset the flag. after setting lock.entry
        // to point to our token, at which point we own the lock
        asm volatile ("pause");
        while (@atomicLoad(u64, @as(*u64, @ptrCast(&token.lock)), .acquire) & 1 != 0) {
            asm volatile ("pause");
        }
    }
}
