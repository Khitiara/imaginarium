const msr = @import("msr.zig");
const util = @import("util");
const crs = @import("ctrl_registers.zig");
const apic = @import("../../apic/apic.zig");
const std = @import("std");

const ext = util.extern_address;

const pause = std.atomic.spinLoopHint;

const ptr_from_physaddr = @import("pmm.zig").ptr_from_physaddr;

export var __bsp_start_spinlock_flag: u8 = 0;

pub fn SmpUtil(comptime Wrapper: type, comptime LocalControlBlock: type, comptime fields: []const []const u8) type {
    const offset = blk: {
        var T = Wrapper;
        var o: usize = 0;
        for (fields) |f| {
            o += @offsetOf(T, f);
            T = @TypeOf(@field(@as(T, undefined), f));
        }
        break :blk o;
    };
    return struct {
        pub const LocalControlBlockPointer = *allowzero addrspace(.gs) const *LocalControlBlock;
        pub const lcb: LocalControlBlockPointer = @ptrFromInt(offset);

        pub fn setup(base_linear_addr: usize) void {
            msr.write(.gs_base, base_linear_addr);
            msr.write(.kernel_gs_base, base_linear_addr);
        }

        pub fn set_tls(linear_addr: usize) void {
            msr.write(.fs_base, linear_addr);
        }
    };
}

const arch = @import("x86_64.zig");
const delay_unsafe = arch.delay_unsafe;

var ap_stacks: []*[8 << 20]u8 = undefined;

pub fn get_local_krnl_stack() *[8 << 20]u8 {
    return ap_stacks[apic.lapic_indices[apic.get_lapic_id()]];
}
pub fn get_local_krnl_stack_top() *anyopaque {
    return @ptrFromInt(@intFromPtr(get_local_krnl_stack()) + (8 << 20));
}

var _cb: *const fn (std.mem.Allocator) void = undefined;
const vmm = @import("vmm.zig");
var bspid: u8 = undefined;

const log = std.log.scoped(.@"hal.smp");

pub fn init(comptime cb: anytype) @typeInfo(@TypeOf(cb)).Fn.return_type.? {
    bspid = apic.get_lapic_id();
    const alloc = vmm.raw_page_allocator.allocator();
    const gpa = vmm.gpa.allocator();
    var raw_ap_stacks = try alloc.alloc([8 << 20]u8, apic.lapics.len - 1);
    ap_stacks = try gpa.alloc(*[8 << 20]u8, apic.lapics.len);
    var stk: usize = 0;
    for (apic.lapics.items(.id), 0..) |id, i| {
        if (id == bspid) {
            ap_stacks[i] = @ptrFromInt(ext("__bootstrap_stack_bottom__"));
        } else if (apic.lapics.items(.enabled)[i] or apic.lapics.items(.online_capable)[i]) {
            ap_stacks[i] = &raw_ap_stacks[stk];
            stk += 1;
        } else {
            log.debug("processor {d} (lapic id {d}) is not usable", .{ i, id });
        }
    }
    return try cb(alloc, gpa);
}

pub fn start_aps(cb: *const fn (std.mem.Allocator) void) !void {
    _cb = cb;

    const ap_start = ext("__ap_trampoline_begin__");
    const ap_end = ext("__ap_trampoline_end__");

    const lnd_ofs = @intFromPtr(ext("_ap_land_")) - @intFromPtr(ap_start);
    const stk_ofs = @intFromPtr(ext("_ap_stk_")) - @intFromPtr(ap_start);
    const cr3_ofs = @intFromPtr(ext("_ap_cr3_")) - @intFromPtr(ap_start);

    const ap_trampoline = ptr_from_physaddr([*]u8, 0x8000);
    @memcpy(ap_trampoline, ap_start[0..(@intFromPtr(ap_end) - @intFromPtr(ap_start))]);
    @as(**const fn () callconv(.Win64) void, @ptrCast(ap_trampoline[lnd_ofs..])).* = &__ap_landing;
    @as(*usize, @ptrCast(ap_trampoline[cr3_ofs..])).* = crs.read(.cr3);
    const ap_stk_ptr: *usize = @ptrCast(ap_trampoline[stk_ofs..]);
    var init_icr: apic.Icr = .{
        .vector = 0,
        .delivery = .init,
        .dest_mode = .physical,
        .assert = false,
        .trigger_mode = .level,
        .shorthand = .none,
        .dest = 0,
    };
    // var sipi_icr: apic.Icr = .{
    //     .vector = 8,
    //     .delivery = .startup,
    //     .dest_mode = .physical,
    //     .assert = false,
    //     .trigger_mode = .edge,
    //     .shorthand = .none,
    //     .dest = 0,
    // };
    for (0..apic.processor_count) |i| {
        const id = apic.lapic_ids[i];
        if (id == bspid) {
            continue;
        }
        ap_stk_ptr.* = @intFromPtr(ap_stacks[i]) + (8 << 20);
        apic.write_register(.esr, @bitCast(@as(u32, 0)));
        init_icr.assert = true;
        init_icr.dest = id;
        apic.write_register(.icr, init_icr);
        pause();
        while (apic.read_register(.icr).pending) {
            pause();
        }
        init_icr.assert = false;
        apic.write_register(.icr, init_icr);
        while (apic.read_register(.icr).pending) {
            pause();
        }
        delay_unsafe(10000000);
    }
}

pub fn wait_for_all_aps() void {
    while (@atomicLoad(u8, &__bsp_start_spinlock_flag, .acquire) == 0) {
        pause();
    }
}

export fn __ap_landing() callconv(.Win64) noreturn {
    @import("gdt.zig").apply();
    @import("idt.zig").load();
    _cb(vmm.gpa.allocator());

    while (true) {}
}
