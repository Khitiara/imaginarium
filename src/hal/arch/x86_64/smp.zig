const msr = @import("msr.zig");
const util = @import("util");
const crs = @import("ctrl_registers.zig");
const apic = @import("../../apic/apic.zig");

const ext = util.extern_address;

pub const ap_start = ext("__ap_trampoline_begin");
pub const ap_end = ext("__ap_trampoline_end");

const ptr_from_physaddr = @import("pmm.zig").ptr_from_physaddr;

export var __bsp_start_spinlock_flag: u8 = 0;

pub fn SmpUtil(comptime LocalControlBlock: type) type {
    return struct {
        pub const LocalControlBlockPointer = *addrspace(.gs) LocalControlBlock;
        pub const lcb: *addrspace(.gs) LocalControlBlock = @ptrFromInt(@alignOf(LocalControlBlock));

        pub fn setup(base_linear_addr: isize) void {
            msr.write(.gs_base, base_linear_addr);
        }
    };
}

const arch = @import("x86_64.zig");
const pause = arch.pause;
const delay_unsafe = arch.delay_unsafe;

var ap_stacks: [][8 << 20]u8 = undefined;

pub fn get_local_krnl_stack() *anyopaque {
    return @ptrFromInt(@intFromPtr(&ap_stacks[apic.lapic_indices[apic.get_lapic_id()]]) + (8 << 20));
}

pub fn init(proc_cnt: u8) !void {
    const bspid = @import("cpuid.zig").cpuid(.type_fam_model_stepping_features, {}).brand_flush_count_id.apic_id;
    const alloc = @import("vmm.zig").raw_page_allocator.allocator();
    ap_stacks = try alloc.alloc([8 << 20]u8, proc_cnt);
    const lnd_ofs = @intFromPtr(ext("_ap_land")) - @intFromPtr(ap_start);
    const stk_ofs = @intFromPtr(ext("_ap_stk")) - @intFromPtr(ap_start);
    const cr3_ofs = @intFromPtr(ext("_ap_cr3")) - @intFromPtr(ap_start);

    const ap_trampoline = ptr_from_physaddr([*]u8, 0x8000);
    @memcpy(ap_trampoline, ap_start[0..(@intFromPtr(ap_end) - @intFromPtr(ap_start))]);
    @as(**const fn () callconv(.Win64) void, @ptrCast(ap_trampoline[lnd_ofs..])).* = &__ap_landing;
    @as(*usize, @ptrCast(ap_trampoline[cr3_ofs..])).* = crs.read(.cr3);
    const ap_stk_ptr: *usize = @ptrCast(ap_trampoline[stk_ofs..]);
    const icr_high = apic.get_register_ptr(apic.RegisterId.icr + 1, apic.IcrHigh);
    const icr_low = apic.get_register_ptr(apic.RegisterId.icr, apic.IcrLow);
    for (0..proc_cnt) |i| {
        if (apic.lapic_ids[i] == bspid) {
            continue;
        }
        ap_stk_ptr.* = @intFromPtr(&ap_stacks[i]) + (8 << 20);
        apic.get_register_ptr(apic.RegisterId.esr, u32).* = 0;
        icr_high.*.dest = i;
        var l = icr_low.*;
        l.delivery = .init;
        l.trigger_mode = .level;
        l.assert = true;
        icr_low.* = l;
        pause();
        while (apic.get_register_ptr(apic.RegisterId.icr).* & (1 << 12) != 0) {
            pause();
        }
        apic.get_register_ptr(apic.RegisterId.icr + 1).* = (apic.get_register_ptr(apic.RegisterId.icr + 1).* & 0x00ffffff) | (i << 24);
        apic.get_register_ptr(apic.RegisterId.icr + 1).* = (apic.get_register_ptr(apic.RegisterId.icr).* & 0xfff00000) | 0x00008500;
        while (apic.get_register_ptr(apic.RegisterId.icr).* & (1 << 12) != 0) {
            pause();
        }
        delay_unsafe(10000000);
    }
}

export fn __ap_landing() callconv(.Win64) noreturn {
    @import("gdt.zig").apply();
    @import("idt.zig").load();
    while (@atomicLoad(u8, &__bsp_start_spinlock_flag, .acquire) == 0) {
        pause();
    }

    while (true) {}
}
