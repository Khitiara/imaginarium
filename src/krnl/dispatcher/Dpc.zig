const util = @import("util");
const Dpc = @This();
const std = @import("std");
const smp = @import("../smp.zig");

pub const Priority = util.PriorityEnum(3);
pub const DpcFn = *const fn (*const Dpc, ?*anyopaque, ?*anyopaque, ?*anyopaque) void;

pub const Pool = std.heap.MemoryPool(Dpc);
pub var pool: Pool = undefined;

priority: Priority,
hook: util.queue.Node = .{},
routine: DpcFn,
args: [3]?*anyopaque,

pub fn run(self: *const Dpc) void {
    // could just do this normally but the concat on args feels more readable imo
    @call(.auto, self.routine, .{self} ++ util.tuple_from_array(self.args));
}

pub fn schedule(self: *Dpc) void {
    smp.lcb.*.dpc_lock.lock(null);
    defer smp.lcb.*.dpc_lock.unlock();
    smp.lcb.*.dpc_queue.add(self);
}