const std = @import("std");
const dispatcher = @import("dispatcher.zig");
const util = @import("util");
const hal = @import("../hal/hal.zig");
const smp = @import("../smp.zig");
const arch = hal.arch;
const apic = hal.apic;
const InterruptRequestPriority = hal.InterruptRequestPriority;
const InterruptVector = hal.InterruptVector;
const lcb = smp.lcb;

pub inline fn handle_interrupt(comptime handler: fn (*arch.SavedRegisterState) void) fn (*arch.SavedRegisterState) callconv(.SysV) void {
    return struct {
        fn f(frame: *arch.SavedRegisterState) callconv(.SysV) void {
            const is_root_interrupt: bool = lcb.*.frame == null;
            defer if (is_root_interrupt) dispatch_interrupt_tail(frame);
            lcb.*.frame = lcb.*.frame orelse frame;
            const vector: InterruptVector = frame.vector.vector;
            _ = hal.set_irql(vector.level, .raise);
            @call(.always_inline, handler, .{frame});
        }
    }.f;
}

fn enter_scheduling_1(_: *arch.SavedRegisterState) void {}
export const enter_scheduling_2 = handle_interrupt(enter_scheduling_1);

pub noinline fn enter_scheduling() void {
    arch.idt.spoof_isr(&enter_scheduling_2);
}

fn enter_thread_ctx_1(frame: *arch.SavedRegisterState) callconv(.SysV) void {
    std.log.debug("entering thread frame, RIP=0x{x:0>16}", .{frame.rip});
    lcb.*.current_thread.?.saved_state.registers = frame.*;
    std.log.debug("returning to thread {{{s}}}", .{lcb.*.current_thread.?.header.id});
}

pub noinline fn enter_thread_ctx() void {
    arch.idt.spoof_isr(&enter_thread_ctx_1);
}

/// progresses downward through the IRQL levels and addresses each in turn if needed
/// this may result in nested interrupts from other IRQLs, *but* the nested interrupt
/// is guaranteed to correctly handle
fn dispatch_interrupt_tail(frame: *arch.SavedRegisterState) void {
    arch.idt.enable();
    var level = lcb.*.irql;
    // higher IRQLs do processing through ISRs rather than fixed logic. loop through to process each IRQL in turn
    while (@intFromEnum(level) > @intFromEnum(InterruptRequestPriority.dpc)) : (level = hal.set_irql(level.lower(), .lower)) {}

    // IRQL:DPC
    {
        var node = blk: {
            const irql = lcb.*.dpc_lock.lock_at(.dpc);
            defer lcb.*.dpc_lock.unlock(irql);
            break :blk lcb.*.dpc_queue.clear();
        };
        while (node) |dpc| {
            node = smp.LocalControlBlock.DpcQueueType.ref_from_optional_node(dpc.hook.next);
            dpc.run();
        }
        _ = hal.set_irql(lcb.*.irql.lower(), .lower);
    }

    // IRQL:DISPATCH
    {
        // once we get here, the frame in the LCB might have been swapped if we reach here
        // from kernel-mode code which is setting a new thread when one previously did not
        // exist, e.g. during startup. if the frame in the LCB is null, the frame in our
        // function parameter should still be correct
        if (lcb.*.frame) |f| {
            frame.* = f.*;
            lcb.*.frame = null;
        }
        dispatcher.scheduler.dispatch(frame);
        _ = hal.set_irql(lcb.*.irql.lower(), .lower);
    }
    std.debug.assert(lcb.*.irql == .passive);
}
