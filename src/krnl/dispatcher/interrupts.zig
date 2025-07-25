const std = @import("std");
const dispatcher = @import("dispatcher.zig");
const util = @import("util");
const hal = @import("../hal/hal.zig");
const smp = @import("../smp.zig");
const arch = hal.arch;
const apic = arch.apic;
const InterruptRequestPriority = hal.InterruptRequestPriority;
const InterruptVector = hal.InterruptVector;
const lcb = smp.lcb;
const log = std.log.scoped(.@"dispatcher.interrupts");

pub var dispatch_vector: InterruptVector = undefined;
pub var dpc_vector: InterruptVector = undefined;

pub fn init_dispatch_interrupts() !void {
    dispatch_vector = try arch.idt.allocate_vector(.dispatch);
    log.debug("dispatch vector: 0x{X:0>2}", .{@as(u8, @bitCast(dispatch_vector))});
    arch.idt.add_handler(.{ .vector = dispatch_vector }, &handle_interrupt(true, dispatcher.scheduler.dispatch), .trap, 0, 0);
    dpc_vector = try arch.idt.allocate_vector(.dispatch);
    log.debug("dpc vector: 0x{X:0>2}", .{@as(u8, @bitCast(dpc_vector))});
    arch.idt.add_handler(.{ .vector = dpc_vector }, &handle_interrupt(true, dispatch_dpcs), .trap, 0, 0);
}

pub inline fn handle_interrupt(comptime eoi: bool, comptime handler: fn (*arch.SavedRegisterState) void) fn (*arch.SavedRegisterState) callconv(.SysV) void {
    return struct {
        fn func(frame: *arch.SavedRegisterState) callconv(.SysV) void {
            lcb.*.frame = lcb.*.frame orelse frame;
            handler(frame);
            if (lcb.*.frame) |f| {
                frame.* = f.*;
                lcb.*.frame = null;
            }
            if (comptime eoi) {
                hal.arch.apic.eoi();
            }
        }
    }.func;
}

pub noinline fn enter_scheduling() void {
    apic.send_ipi(.{
        .vector = @bitCast(dispatch_vector),
        .delivery = .fixed,
        .shorthand = .self,
        .dest_mode = .physical,
        .dest = apic.get_lapic_id(),
        .trigger_mode = .edge,
    });
}

fn enter_thread_ctx_1(frame: *arch.SavedRegisterState) callconv(.SysV) void {
    std.log.debug("entering thread frame, RIP=0x{x:0>16}", .{frame.rip});
    lcb.*.current_thread.?.saved_state.registers = frame.*;
    std.log.debug("returning to thread {{{s}}}", .{lcb.*.current_thread.?.header.id});
}

pub noinline fn enter_thread_ctx() void {
    arch.idt.spoof_isr(&enter_thread_ctx_1);
}

fn dispatch_dpcs(_: *arch.SavedRegisterState) void {
    var node = blk: {
        const irql = lcb.*.dpc_lock.lock_cli();
        defer lcb.*.dpc_lock.unlock_sti(irql);
        break :blk lcb.*.dpc_queue.clear();
    };
    while (node) |dpc| {
        node = smp.LocalControlBlock.DpcQueueType.ref_from_optional_node(dpc.hook.next);
        dpc.run();
    }
}
