const util = @import("util");
const Dpc = @This();

pub const Priority = util.PriorityEnum(3);
pub const DpcFn = *const fn (*const Dpc, ?*anyopaque, ?*anyopaque, ?*anyopaque) void;

priority: Priority,
procid: u8,
hook: util.queue.Node,
routine: DpcFn,
args: [3]?*anyopaque,
