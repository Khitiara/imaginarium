const msr = @import("msr.zig");
const util = @import("util");
const crs = @import("ctrl_registers.zig");
const apic = @import("apic/apic.zig");
const std = @import("std");

const ext = util.extern_address;

const pause = std.atomic.spinLoopHint;

export var __bsp_start_spinlock_flag: u8 = 0;

const hal = @import("../../hal.zig");
const arch = @import("arch.zig");
const delay_unsafe = arch.delay_unsafe;

const ksmp = @import("../../../smp.zig");

var ap_stacks: []*[8 << 20]u8 = undefined;

pub fn get_local_krnl_stack() *[8 << 20]u8 {
    return ap_stacks[ksmp.prcbs[apic.get_lapic_id()].lcb.info.lapic_index];
}
pub fn get_local_krnl_stack_top() *anyopaque {
    return get_local_krnl_stack() + (8 << 20);
}

var _cb: *const fn (std.mem.Allocator) void = undefined;
var bspid: u8 = undefined;

const log = std.log.scoped(.@"hal.smp");

pub const ArchPrcb = extern struct {
    gdt: arch.gdt.Gdt,
    tss: arch.gdt.TssBlock,

    pub fn init(prcb: *ArchPrcb) void {
        prcb.gdt = arch.gdt.gdt;
        prcb.tss = arch.gdt.tss;
        prcb.gdt.tss.set_base(@intFromPtr(&prcb.tss));
    }
};

pub fn init() !void {
    bspid = apic.get_lapic_id();
    const alloc = hal.mm.pool.pool_page_allocator;
    const gpa = hal.mm.pool.pool_allocator;
    ap_stacks = try gpa.alloc(*[8 << 20]u8, apic.lapics.len);
    var stk: usize = 0;
    for (apic.lapics.items(.id), 0..) |id, i| {
        if (id == bspid) {
            ap_stacks[i] = @ptrFromInt(ext("__bootstrap_stack_bottom__"));
        } else if (apic.lapics.items(.enabled)[i] or apic.lapics.items(.online_capable)[i]) {
            ap_stacks[i] = try alloc.create([8 << 20]u8);
            stk += 1;
        } else {
            log.debug("processor {d} (lapic id {d}) is not usable", .{ i, id });
        }
    }
}
