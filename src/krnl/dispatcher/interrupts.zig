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

pub inline fn handle_interrupt(handler: fn (*arch.SavedRegisterState) void) fn (*arch.SavedRegisterState) callconv(.Win64) void {
    return struct {
        fn f(frame: *arch.SavedRegisterState) callconv(.Win64) void {
            const is_root_interrupt: bool = lcb().frame == null;
            defer if (is_root_interrupt) dispatch_interrupt_tail(frame);
            lcb().frame = lcb().frame orelse frame;
            const vector: InterruptVector = @bitCast(@intFromEnum(frame.interrupt_number));
            _ = set_irql(vector.level);
            @call(.always_inline, handler, .{frame});
        }
    }.f;
}

fn enter_scheduling_1(_: *arch.SavedRegisterState) void {}
export const enter_scheduling_2 = handle_interrupt(enter_scheduling_1);

pub noinline fn enter_scheduling() void {
    arch.x86_64.idt.spoof_isr(&enter_scheduling_2);
}

fn enter_thread_ctx_1(frame: *arch.SavedRegisterState) callconv(.Win64) void {
    std.log.debug("entering thread frame, RIP=0x{x:0>16}", .{frame.rip});
    lcb().current_thread.?.saved_state.registers = frame.*;
    std.log.debug("returning to thread {}", .{lcb().current_thread.?.header.id});
}

pub noinline fn enter_thread_ctx() void {
    arch.x86_64.idt.spoof_isr(&enter_thread_ctx_1);
}

fn set_irql(level: InterruptRequestPriority) InterruptRequestPriority {
    const rest = lcb().irql_lock.lock();
    defer lcb().irql_lock.unlock(rest);
    lcb().irql = level;
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

    while (lasts[idx] < 0x10) {
        const l: u4 = @truncate(@atomicRmw(u8, &lasts[idx], .Add, 1, .acq_rel));
        const v: InterruptVector = .{ .vector = l, .level = level };
        if (arch.is_vector_free(@bitCast(v))) {
            return v;
        }
    }
    return error.out_of_vectors;
}

/// progresses downward through the IRQL levels and addresses each in turn if needed
/// this may result in nested interrupts from other IRQLs, *but* the nested interrupt
/// is guaranteed to correctly handle
fn dispatch_interrupt_tail(frame: *arch.SavedRegisterState) void {
    arch.enable_interrupts();
    var level = smp.lcb().irql;
    // higher IRQLs do processing through ISRs rather than fixed logic. loop through to process each IRQL in turn
    while (@intFromEnum(level) > @intFromEnum(InterruptRequestPriority.dpc)) : (level = set_irql(level.lower())) {}

    // IRQL:DPC
    {
        // TODO: run any queued DPCs
        _ = set_irql(lcb().irql.lower());
    }

    // IRQL:DISPATCH
    {
        // once we get here, the frame in the LCB might have been swapped if we reach here
        // from kernel-mode code which is setting a new thread when one previously did not
        // exist, e.g. during startup. if the frame in the LCB is null, the frame in our
        // function parameter should still be correct
        if (lcb().frame) |f| {
            frame.* = f.*;
            lcb().frame = null;
        }
        dispatcher.scheduler.dispatch(frame);
        _ = set_irql(lcb().irql.lower());
    }
    std.debug.assert(lcb().irql == .passive);
}
