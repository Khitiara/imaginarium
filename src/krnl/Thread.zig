const dispatcher = @import("dispatcher.zig");
const queue = @import("util").queue;

pub const Semaphore = @import("thread/Semaphore.zig");

header: dispatcher.DispatcherObject = .{ .kind = .thread },
wait_list: queue.DoublyLinkedList(dispatcher.wait_block.WaitBlock, "thread_wait_list") = .{},
