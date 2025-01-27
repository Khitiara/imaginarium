//! the kernel memory manager

pub const mminit = @import("mminit.zig");

const std = @import("std");
const arch = @import("../arch/arch.zig");
const Pfi = @import("pfmdb.zig").Pfi;

pub inline fn pages_spanned(start: usize, len: usize) usize {
    return ((start & comptime (std.mem.page_size - 1)) + len) / std.mem.page_size;
}

pub inline fn flush_local_tlb() void {
    arch.control_registers.write(.cr3, arch.control_registers.read(.cr3));
}

pub const PfiBreakdown = packed union {
    pfi: Pfi,
    breakdown: packed struct(Pfi) {
        pte: u9,
        pde: u9,
        ppe: u9,
        pxe: u9,
    },
    pde_breakdown: packed struct(Pfi) {
        pte: u9,
        pde: u27,
    },
    ppe_breakdown: packed struct(Pfi) {
        pte: u9,
        pde: u9,
        ppe: u18,
    }
};

pub var valid_pte: @import("pte.zig").Pte = .{
    .valid = .{
        .writable = true,
        .user_mode = false,
        .write_through = false,
        .cache_disable = true,
        .pat_size = false,
        .global = false,
        .copy_on_write = false,
        .sw_dirty = false,
        .addr = .{ .pfi = 0 },
        .pk = 0,
        .xd = false,
    },
};
