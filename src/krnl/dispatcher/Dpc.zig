const util = @import("util");
const Dpc = @This();
const std = @import("std");

pub const Priority = util.PriorityEnum(3);
pub const DpcFn = *const fn (*const Dpc, ?*anyopaque, ?*anyopaque, ?*anyopaque) void;

pub const Pool = std.heap.MemoryPool(Dpc);
pub var pool: Pool = undefined;

priority: Priority,
procid: u8,
hook: util.queue.Node,
routine: DpcFn,
args: [3]?*anyopaque,
