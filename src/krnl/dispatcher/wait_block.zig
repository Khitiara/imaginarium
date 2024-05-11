const queue = @import("util").queue;
const Thread = @import("../thread/Thread.zig");
const dispatcher = @import("dispatcher.zig");
const ob = @import("../objects/ob.zig");

pub const WaitKey = union(enum) {
    wait_single: void,
    wait_any: u16,
    wait_all: u16,
};

pub const WaitBlock = struct {
    wait_queue: queue.Node,
    thread_wait_list: queue.DoublyLinkedNode,
    key: WaitKey,
    thread: *Thread,
    target: *ob.Object,
};