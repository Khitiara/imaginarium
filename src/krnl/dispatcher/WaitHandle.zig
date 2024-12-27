//! A wait handle is a generalization of the ability to wait on varying kinds of objects in varying ways
//! e.g. A thread will expose a WaitHandle for the join operation, a RWLock will expose a shared WaitHandle and
//! an exclusive WaitHandle for readers and writers respectively, and so forth.

const dispatcher = @import("dispatcher.zig");
const WaitBlock = dispatcher.WaitBlock;
const collections = @import("collections");
const queue = collections.queue;
const Thread = @import("../thread/Thread.zig");
const QueuedSpinlock = @import("../hal/QueuedSpinLock.zig");

const WaitHandle = @This();
const WaitQueue = queue.DoublyLinkedList(WaitBlock, "wait_queue");
wait_lock: QueuedSpinlock = .{},
wait_queue: WaitQueue = .{},
/// when called, wait_lock MUST be already aquired.
/// checks if a wait is necessary, queuing the thread if so
/// if a wait is required, the implementation MUST call enqueue_wait
/// this function is used in the implementation of wait_for_single_object
check_wait: *const fn (*WaitHandle, *Thread) error{OutOfMemory}!bool,

pub fn enqueue_wait(target: *WaitHandle, thread: *Thread) !void {
    const block: *WaitBlock = try WaitBlock.pool.create();
    block.thread = thread;
    block.target = target;
    target.wait_queue.add_back(block);
    thread.wait_list.add_back(block);
}

pub fn release_one(handle: *WaitHandle) bool {
    if(handle.wait_queue.remove_front()) |block| {
        dispatcher.scheduler.signal_wait_block(block, true);
        return true;
    }
    return false;
}

pub fn release_all(handle: *WaitHandle) void {
    var head = handle.wait_queue.clear();
    while(head) |n| : (head = WaitQueue.next(n)) {
        dispatcher.scheduler.signal_wait_block(n, true);
    }
}