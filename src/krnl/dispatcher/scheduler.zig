const std = @import("std");
const dispatcher = @import("dispatcher.zig");
const util = @import("util");
const hal = @import("hal");
const smp = @import("../smp.zig");
const arch = hal.arch;
const apic = hal.apic;
const InterruptRequestPriority = dispatcher.InterruptRequestPriority;
const lcb = smp.lcb;
const Thread = @import("../thread/Thread.zig");

pub fn dispatch(frame: *arch.SavedRegisterState) void {
    // TODO: thread scheduling fun times
    // for now, just check if the current thread is lower prio then the head of the queue
    while (true) {
        if (lcb.standby_thread) |stby| {
            // something in standby
            if (lcb.current_thread) |cur| {
                // have both a standby and a current thread. check if the priority is wrong

                // lower = more prioritized
                const restore = b: {
                    if (@intFromEnum(stby.priority) < @intFromEnum(cur.priority)) {
                        // priority is swapped, so do the three way swap
                        // stby -> curr
                        // curr -> queue
                        // queue head -> stby
                        std.debug.assert(lcb.frame != null);
                        cur.saved_state = frame.*;
                        cur.set_state(.running, .assigned);
                        frame.* = stby.saved_state.registers;
                        lcb.current_thread = stby;
                        stby.set_state(.standby, .running);

                        // grab the lock a bit early to put the old running thread into the queue
                        const r = lcb.local_dispatcher_lock.lock();
                        lcb.local_dispatcher_queue.add(cur);
                        lcb.standby_thread = lcb.local_dispatcher_queue.dequeue();
                        if (lcb.standby_thread) |new_stby| {
                            new_stby.set_state(.assigned, .standby);
                        }
                        break :b r;
                    } else {
                        break :b lcb.local_dispatcher_lock.lock();
                    }
                };
                defer lcb.local_dispatcher_lock.unlock(restore);
                // check if theres anything in the queue, and swap standby and the head if needed
                if (lcb.local_dispatcher_queue.peek()) |peek| {
                    if (@intFromEnum(peek.priority) < @intFromEnum(stby.priority)) {
                        stby.set_state(.standby, .assigned);
                        peek.set_state(.assigned, .standby);
                        lcb.local_dispatcher_queue.add(stby);
                        lcb.standby_thread = lcb.local_dispatcher_queue.dequeue().?;
                    }
                }
            } else {
                // nothing running but we have a standby, so move that up to run
                const restore = lcb.local_dispatcher_lock.lock();
                defer lcb.local_dispatcher_lock.unlock(restore);
                lcb.current_thread = stby;
                stby.set_state(.standby, .running);
                // move the queue head up to standby
                lcb.standby_thread = lcb.local_dispatcher_queue.dequeue();
                if (lcb.standby_thread) |new_stby| {
                    new_stby.set_state(.assigned, .standby);
                }
                // and set up the LCB to restore the saved register state of the thread
                // the caller should have the lcb already set up with a frame pointer
                frame.* = stby.saved_state.registers;
            }
        } else {
            // nothing in standby
            const restore = lcb.local_dispatcher_lock.lock();
            defer lcb.local_dispatcher_lock.unlock(restore);
            if (lcb.local_dispatcher_queue.dequeue()) |queued| {
                const tr = queued.lock.lock();
                defer queued.lock.unlock(tr);
                std.debug.assert(queued.state == .assigned);
                queued.state = .standby;
            } else {
                return;
            }
        }
    }
}
