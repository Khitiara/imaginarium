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
    const l: *smp.LocalControlBlock = lcb();
    // TODO: thread scheduling fun times
    // for now, just check if the current thread is lower prio then the head of the queue
    while (true) {
        if (l.standby_thread) |stby| {
            // something in standby
            if (l.current_thread) |cur| {
                // have both a standby and a current thread. check if the priority is wrong

                // lower = more prioritized
                const restore = b: {
                    if (@intFromEnum(stby.priority) < @intFromEnum(cur.priority)) {
                        // priority is swapped, so do the three way swap
                        // stby -> curr
                        // curr -> queue
                        // queue head -> stby
                        std.debug.assert(l.frame != null);
                        cur.saved_state.registers = frame.*;
                        cur.set_state(.running, .assigned);
                        frame.* = stby.saved_state.registers;
                        l.current_thread = stby;
                        stby.set_state(.standby, .running);

                        // grab the lock a bit early to put the old running thread into the queue
                        const r = l.local_dispatcher_lock.lock();
                        if (!cur.header.id.eql(smp.idle_thread_id)) {
                            l.local_dispatcher_queue.add(cur);
                        }
                        if (l.local_dispatcher_queue.dequeue()) |new_stby| {
                            l.standby_thread = new_stby;
                            new_stby.set_state(.assigned, .standby);
                        }
                        break :b r;
                    } else {
                        break :b l.local_dispatcher_lock.lock();
                    }
                };
                defer l.local_dispatcher_lock.unlock(restore);
                // check if theres anything in the queue, and swap standby and the head if needed
                if (l.local_dispatcher_queue.peek()) |peek| {
                    if (@intFromEnum(peek.priority) < @intFromEnum(stby.priority)) {
                        stby.set_state(.standby, .assigned);
                        peek.set_state(.assigned, .standby);
                        l.local_dispatcher_queue.add(stby);
                        l.standby_thread = l.local_dispatcher_queue.dequeue().?;
                    }
                }
                // in this branch, there is a current thread so we just return now
                return;
            } else {
                // nothing running but we have a standby, so move that up to run
                const restore = l.local_dispatcher_lock.lock();
                defer l.local_dispatcher_lock.unlock(restore);
                l.current_thread = stby;
                stby.set_state(.standby, .running);
                // and set up the LCB to restore the saved register state of the thread
                // the caller should have the lcb already set up with a frame pointer
                frame.* = stby.saved_state.registers;
                // move the queue head up to standby
                if (l.local_dispatcher_queue.dequeue()) |new_stby| {
                    l.standby_thread = new_stby;
                    new_stby.set_state(.assigned, .standby);
                }
                // and we're done. this is the fast path
                return;
            }
        } else {
            // nothing in standby
            const restore = l.local_dispatcher_lock.lock();
            defer l.local_dispatcher_lock.unlock(restore);
            if (l.local_dispatcher_queue.dequeue()) |queued| {
                const tr = queued.lock.lock();
                defer queued.lock.unlock(tr);
                std.debug.assert(queued.state == .assigned);
                queued.state = .standby;
                l.standby_thread = queued;
                // and loop around to figure out standby and running
            } else {
                // nothing on standby and nothing in queue
                // if theres nothing running then just stick the idle thread in
                // and then return with something set to run
                if (l.current_thread == null) {
                    l.current_thread = l.idle_thread;
                    l.idle_thread.set_state(.assigned, .running);
                    frame.* = l.idle_thread.saved_state.registers;
                }
                return;
            }
        }
    }
}
