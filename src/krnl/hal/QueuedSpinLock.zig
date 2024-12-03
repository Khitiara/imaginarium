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
};

/// the TAIL of the wait queue, if anyone is waiting.
/// the current holder of the lock maintains a reference to the head of the queue
/// which doubles as its token of ownership of the lock
entry: ?*Token = null,

pub fn lock(self: *QueuedSpinLock, token: *Token) void {
    self.lock_at(token, .dispatch);
}

pub fn lock_at(self: *QueuedSpinLock, token: *Token, tgt: hal.InterruptRequestPriority) void {
    const irql = hal.fetch_set_irql(tgt, .raise);
    self.lock_unsafe(token);
    token.saved_irql = irql;
}

pub fn lock_unsafe(self: *QueuedSpinLock, token: *Token) void {
    // I dont trust RLS enough to just return this while still using a pointer to it
    // so we take a pointer and assign over the contents instead
    token.* = .{
        .lock = self,
        .next = null,
        .saved_irql = undefined,
    };
    // atomically exchange ourself into the lock's tail pointer.
    if (@atomicRmw(?*Token, &self.entry, .Xchg, token, .acq_rel)) |tail| {
        // there's an old tail, which means theres an old head, which means the lock is taken

        // set the wait flag before append so we can get freed immediately
        @as(*u64, @ptrCast(&token.lock)).* |= 1;
        // and append ourself on the queue
        tail.next = token;

        // do..while loop until the wait flag is unset.
        // when the lock is freed by the current holder
        // they will unset the flag. after setting lock.entry
        // to point to our token, at which point we own the lock
        asm volatile ("pause");
        while (@as(*u64, @ptrCast(&token.lock)).* & 1 != 0) {
            asm volatile ("pause");
        }
    }
}

pub fn unlock(token: *Token) void {
    unlock_unsafe(token);
    _ = hal.set_irql(token.saved_irql, .lower);
}

pub fn unlock_unsafe(token: *Token) void {
    // quick load of the next in line
    var next = @atomicLoad(?*Token, &token.next, .acquire);
    if (next == null) {
        // if noone else is in line, then we are the tail.
        // thus, do a compare-exchange to null out the lock's
        // entry pointer atomically.
        const l: *QueuedSpinLock = @ptrFromInt(@intFromPtr(token.lock) & (~@as(usize, 1)));
        if (@cmpxchgStrong(?*Token, &l.entry, token, null, .acq_rel, .acquire) == null) {
            // the compare-exchange succeeded, which means that the atomicRmw in lock_unsafe
            // was not executed since the atomicLoad above. therefore, the lock is properly freed
            // and we can just return
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
