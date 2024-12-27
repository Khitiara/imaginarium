const util = @import("util");
const Dpc = @This();
const std = @import("std");
const smp = @import("../smp.zig");
const apic = @import("../hal/apic/apic.zig");
const collections = @import("collections");

pub const Priority = util.PriorityEnum(3);
pub const DpcFn = *const fn (*Dpc, ?*anyopaque, ?*anyopaque, ?*anyopaque) void;

pub const Pool = std.heap.MemoryPool(Dpc);
pub var pool: Pool = undefined;

priority: Priority,
hook: collections.queue.Node = .{},
routine: DpcFn,
args: [3]?*anyopaque,

pub fn run(self: *Dpc) void {
    // could just do this normally but the concat on args feels more readable imo
    @call(.auto, self.routine, .{self} ++ util.tuple_from_array(self.args));
}

pub fn init_and_schedule(prio: Priority, routine: anytype, args: [3]?*anyopaque) !*Dpc {
    const dpc = try pool.create();
    dpc.* = .{
        .priority = prio,
        .routine = @ptrCast(routine),
        .args = args,
    };
    schedule(dpc);
    return dpc;
}

pub fn schedule(self: *Dpc) void {
    const irql = smp.lcb.*.dpc_lock.lock();
    defer smp.lcb.*.dpc_lock.unlock(irql);
    smp.lcb.*.dpc_queue.add(self);

    apic.send_ipi(.{
        .vector = @bitCast(@import("interrupts.zig").dpc_vector),
        .delivery = .fixed,
        .shorthand = .self,
        .dest_mode = .physical,
        .dest = apic.get_lapic_id(),
        .trigger_mode = .edge,
    });
}

pub fn deinit(self: *Dpc) void {
    pool.destroy(self);
}