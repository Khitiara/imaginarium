const std = @import("std");
const queue = @import("collections").queue;
const Thread = @import("../thread/Thread.zig");
const dispatcher = @import("dispatcher.zig");
const ob = @import("../objects/ob.zig");

wait_queue: queue.DoublyLinkedNode,
thread_wait_list: queue.DoublyLinkedNode,
thread: *Thread,
target: *dispatcher.WaitHandle,

pub const Pool = std.heap.MemoryPool(@This());
pub var pool: Pool = undefined;