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
const QueuedSpinlock = hal.QueuedSpinLock;

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
    if (l.info.apic_id != target) {
        // TODO trampoline into a DPC on the target processor
        // DPC execution is not implemented yet so for now dont bother and just eat the lock penalty
    }
    const irql = l.local_dispatcher_lock.lock();
    defer l.local_dispatcher_lock.unlock(irql);
    thread.set_state(.ready, .assigned);
    l.local_dispatcher_queue.add(thread);
}

pub fn signal_wait_block(block: *WaitBlock, already_removed: bool) void {
    const thread = block.thread;
    var tltok: QueuedSpinlock.Token = undefined;
    var wltok: QueuedSpinlock.Token = undefined;
    {
        // grab the wait lock
        thread.wait_lock.lock(&tltok);
        defer tltok.unlock();
        switch (thread.wait_type) {
            .all => {
                // remove the block from the list
                thread.wait_list.remove(block);
                if (!already_removed) {
                    // remove it from its handle's wait queue
                    block.target.wait_lock.lock_unsafe(&wltok);
                    defer wltok.unlock_unsafe();
                    block.target.wait_queue.remove(block);
                }
                // and destroy it
                WaitBlock.pool.destroy(block);
                // if the thread is waiting on other stuff then return
                if (thread.wait_list.length() != 0) return;
            },
            .any => {
                // waiting on anything and something finished, clear the list and go
                // clear returns the raw linked list but removes the tracking by the
                // list struct so we can use it to iterate and free
                var n = thread.wait_list.clear();
                while (n) |node| {
                    n = Thread.WaitListType.ref_from_optional_node(node.thread_wait_list.next);
                    if(node != block or !already_removed){
                        // remove it from its handle's wait queue
                        node.target.wait_lock.lock_unsafe(&wltok);
                        defer wltok.unlock_unsafe();
                        node.target.wait_queue.remove(node);
                    }
                    // and destroy the node
                    WaitBlock.pool.destroy(node);
                }
            },
        }
    }
    // if we got here then either it was a waitany or theres nothing left for the thread to wait on
    thread.set_state(.blocked, .ready);
    schedule(thread, null);
}

inline fn set_running(l: *smp.LocalControlBlock, thread: *Thread, expected: Thread.State, frame: *arch.SavedRegisterState) void {
    l.current_thread = thread;
    thread.set_state(expected, .running);
    frame.* = thread.saved_state.registers;
    // smp.set_tls_base(thread);
}

pub fn dispatch(frame: *arch.SavedRegisterState) void {
    const l: *smp.LocalControlBlock = lcb.*;
    // TODO: cross-processor thread scheduling fun times

    // if we need to yield the thread then do that
    if (l.force_yield) if (l.current_thread) |thread| {
        thread.saved_state.registers = frame.*;
        const irql = smp.lcb.*.local_dispatcher_lock.lock_at(.sync);
        defer smp.lcb.*.local_dispatcher_lock.unlock(irql);
        thread.set_state(.running, .assigned);
        smp.lcb.*.local_dispatcher_queue.add(thread);
        l.current_thread = null;
    };
    l.force_yield = false;

    // for now, just check if the current thread is lower prio then the head of the queue
    while (true) {
        if (l.standby_thread) |stby| {
            // something in standby
            if (l.current_thread) |cur| {
                // have both a standby and a current thread. check if the priority is wrong
                var irql: hal.InterruptRequestPriority = undefined;
                // lower = more prioritized
                if (@intFromEnum(stby.priority) < @intFromEnum(cur.priority)) {
                    // priority is swapped, so do the three way swap
                    // stby -> curr
                    // curr -> queue
                    // queue head -> stby
                    std.debug.assert(l.frame != null);
                    cur.saved_state.registers = frame.*;
                    cur.set_state(.running, .assigned);
                    set_running(l, stby, .standby, frame);

                    // grab the lock a bit early to put the old running thread into the queue
                    irql = l.local_dispatcher_lock.lock_at(.sync);
                    if (!cur.header.id.eql(smp.idle_thread_id)) {
                        l.local_dispatcher_queue.add(cur);
                    }
                    if (l.local_dispatcher_queue.dequeue()) |new_stby| {
                        l.standby_thread = new_stby;
                        new_stby.set_state(.assigned, .standby);
                    }
                } else {
                    irql = l.local_dispatcher_lock.lock_at(.sync);
                }
                defer l.local_dispatcher_lock.unlock(irql);
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
                const irql = l.local_dispatcher_lock.lock_at(.sync);
                defer l.local_dispatcher_lock.unlock(irql);
                set_running(l, stby, .standby, frame);
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
            const irql = l.local_dispatcher_lock.lock_at(.sync);
            defer l.local_dispatcher_lock.unlock(irql);
            if (l.local_dispatcher_queue.dequeue()) |queued| {
                // move queued to standby
                queued.set_state(.assigned, .standby);
                l.standby_thread = queued;
                // and loop around to figure out standby and running
            } else {
                // nothing on standby and nothing in queue
                // if theres nothing running then just stick the idle thread in
                // and then return with something set to run
                if (l.current_thread == null) {
                    set_running(l, l.idle_thread, .assigned, frame);
                }
                return;
            }
        }
    }
}
