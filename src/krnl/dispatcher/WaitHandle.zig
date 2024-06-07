//! A wait handle is a generalization of the ability to wait on varying kinds of objects in varying ways
//! e.g. A thread will expose a WaitHandle for the join operation, a RWLock will expose a shared WaitHandle and
//! an exclusive WaitHandle for readers and writers respectively, and so forth.

const dispatcher = @import("dispatcher.zig");
const WaitBlock = dispatcher.WaitBlock;
const util = @import("util");
const queue = util.queue;

wait_lock: dispatcher.SpinLockIRQL = .{ .set_irql = .passive },
wait_queue: queue.DoublyLinkedList(WaitBlock, "wait_queue") = .{},