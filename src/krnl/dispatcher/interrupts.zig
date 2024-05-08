const std = @import("std");
const dispatcher = @import("dispatcher.zig");
const util = @import("util");
const hal = @import("hal");
const smp = @import("../smp.zig");
const arch = hal.arch;
const apic = hal.apic;
const InterruptRequestPriority = dispatcher.InterruptRequestPriority;
const lcb = smp.lcb;

pub const InterruptVector = packed struct(u8) {
    vector: u4,
    level: InterruptRequestPriority,
};

pub inline fn handle_interrupt(handler: fn (*arch.SavedRegisterState) void) fn (*arch.SavedRegisterState) void {
    return struct {
        fn f(frame: *arch.SavedRegisterState) void {
            const is_root_interrupt: bool = lcb.frame == null;
            defer if (is_root_interrupt) dispatch_interrupt_tail(frame);
            lcb.frame = lcb.frame orelse frame;
            const vector: InterruptVector = @bitCast(frame.interrupt_number);
            set_irql(vector.level);
            @call(.always_inline, handler, .{frame});
        }
    }.f;
}

fn set_irql(level: InterruptRequestPriority) InterruptRequestPriority {
    const rest = lcb.irql_lock.lock();
    defer lcb.irql_lock.unlock(rest);
    lcb.irql = level;
    apic.get_register_ptr(apic.RegisterId.tpr, InterruptRequestPriority).* = level;
    return level;
}

var lasts: [14]u8 = .{0} ** 14;
var vectors_lock: util.SpinLock = .{};
pub fn allocate_vector(level: InterruptRequestPriority) !InterruptVector {
    if (level == .passive) {
        return error.cannot_allocate_passive_interrupt;
    }
    const idx = @intFromEnum(level) - 2;
    const restore = vectors_lock.lock();
    defer vectors_lock.unlock(restore);
    if (lasts[idx] >= 0x10) {
        return error.out_of_vectors;
    }
    if (level == .high and lasts[idx] >= 0xF) {
        return error.out_of_vectors;
    }
    return .{ .vector = @truncate(@atomicRmw(u8, &lasts[idx], .Add, 1, .acq_rel)), .level = level };
}

/// progresses downward through the IRQL levels and addresses each in turn if needed
/// this may result in nested interrupts from other IRQLs, *but* the nested interrupt
/// is guaranteed to correctly handle
fn dispatch_interrupt_tail(frame: *arch.SavedRegisterState) void {
    var level = smp.lcb.irql;
    // higher IRQLs do processing through ISRs rather than fixed logic. loop through to process each IRQL in turn
    while (@intFromEnum(level) > @intFromEnum(InterruptRequestPriority.dpc)) : (level = set_irql(level.lower())) {}

    // IRQL:DPC
    {
        // TODO: run any queued DPCs
        _ = set_irql(lcb.irql.lower());
    }

    // IRQL:DISPATCH
    {
        // once we get here, the frame in the LCB might have been swapped if we reach here
        // from kernel-mode code which is setting a new thread when one previously did not
        // exist, e.g. during startup. if the frame in the LCB is null, the frame in our
        // function parameter should still be correct
        if (lcb.frame) |f| {
            frame.* = f.*;
            lcb.frame = null;
        }
        dispatcher.scheduler.dispatch(frame);
        _ = set_irql(lcb.irql.lower());
    }
    std.debug.assert(lcb.irql == .passive);
}
