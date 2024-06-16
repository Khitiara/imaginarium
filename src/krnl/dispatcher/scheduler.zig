const std = @import("std");
const dispatcher = @import("dispatcher.zig");
const util = @import("util");
const hal = @import("../hal/hal.zig");
const smp = @import("../smp.zig");
const arch = hal.arch;
const apic = hal.apic;
const InterruptRequestPriority = dispatcher.InterruptRequestPriority;
const lcb = smp.lcb;
const Thread = @import("../thread/Thread.zig");
const Dpc = dispatcher.Dpc;
const WaitBlock = dispatcher.WaitBlock;

fn schedule_dpc(_: *const Dpc, thread_opaque: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) void {
    const thread: *Thread = @ptrCast(thread_opaque.?);
    schedule(thread);
}

pub fn cancel(alloc: std.mem.Allocator, wait: *WaitBlock) void {
    cancel_impl(alloc, wait, false);
}

fn cancel_impl(alloc: std.mem.Allocator, wait: *WaitBlock, from_waitall_finish: bool) void {
    defer alloc.destroy(wait);
    const k1 = wait.target.wait_lock.lock();
    defer wait.target.wait_lock.unlock(k1);
    wait.target.wait_queue.remove(wait);
    if (from_waitall_finish) {
        const k2 = wait.thread.lock.lock();
        defer wait.thread.lock.unlock(k2);
        wait.thread.wait_list.remove(wait);
    }
}

/// schedule a thread to the given processor, or the thread's last processor, if no processor is given
/// that processor is responsible for offloading it elsewhere if needed
/// final version will use DPC to get onto other processors when scheduling there
pub fn schedule(thread: *Thread, processor: ?u8) void {
    const l: *smp.LocalControlBlock = lcb.*;
    const target = processor orelse thread.affinity.last_processor;
    if (l.apic_id != target) {
        // TODO trampoline into a DPC on the target processor
        // DPC execution is not implemented yet so for now dont bother and just eat the lock penalty
    }
    const key = l.local_dispatcher_lock.lock();
    defer l.local_dispatcher_lock.unlock(key);
    thread.set_state(.ready, .assigned);
    l.local_dispatcher_queue.add(thread);
}

pub fn signal_wait_block(alloc: std.mem.Allocator, thread: *Thread, block: *WaitBlock) void {
    {
        const key = thread.lock.lock();
        defer thread.lock.unlock(key);
        switch (thread.wait_type) {
            .All => {
                thread.wait_list.remove(block);
                alloc.destroy(block);
                if (thread.wait_list.impl.len != 0) return;
            },
            .Any => {
                var n = thread.wait_list.clear();
                if (n) {
                    while (n) |node| {
                        n = node.next;
                        alloc.destroy(node);
                    }
                } else {
                    @panic("Thread signalled to end WaitAny with nothing in wait list!");
                }
            },
        }
        thread.set_state(.blocked, .ready);
    }
    schedule(thread, null);
}

pub fn dispatch(frame: *arch.SavedRegisterState) void {
    const l: *smp.LocalControlBlock = lcb.*;
    // TODO: cross-processor thread scheduling fun times
    // for now, just check if the current thread is lower prio then the head of the queue
    while (true) {
        if (l.standby_thread) |stby| {
            // something in standby
            if (l.current_thread) |cur| {
                // have both a standby and a current thread. check if the priority is wrong

                // lower = more prioritized
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
                    smp.set_tls_base(stby);

                    // grab the lock a bit early to put the old running thread into the queue
                    l.local_dispatcher_lock.lock();
                    if (!cur.header.id.eql(smp.idle_thread_id)) {
                        l.local_dispatcher_queue.add(cur);
                    }
                    if (l.local_dispatcher_queue.dequeue()) |new_stby| {
                        l.standby_thread = new_stby;
                        new_stby.set_state(.assigned, .standby);
                    }
                } else {
                    l.local_dispatcher_lock.lock();
                }
                defer l.local_dispatcher_lock.unlock();
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
                l.local_dispatcher_lock.lock();
                defer l.local_dispatcher_lock.unlock();
                l.current_thread = stby;
                stby.set_state(.standby, .running);
                smp.set_tls_base(stby);
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
            l.local_dispatcher_lock.lock();
            defer l.local_dispatcher_lock.unlock();
            if (l.local_dispatcher_queue.dequeue()) |queued| {
                queued.lock.lock();
                defer queued.lock.unlock();
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
                    smp.set_tls_base(l.idle_thread);
                    frame.* = l.idle_thread.saved_state.registers;
                }
                return;
            }
        }
    }
}
