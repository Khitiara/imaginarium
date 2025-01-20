//! helpers and constants for the virtual memory layout
//!
//! the memory layout is as follows:
//! ================================
//! 0x0000_0000_0000_0000..0x0000_7FFF_FFFF_0000: user mode
//! 0x0000_7FFF_FFFF_0000..0x0000_8000_0000_0000: no access
//!
//! 0x0000_8000_0000_0000..0xFFFF_8000_0000_0000: not canonical
//!
//! 0xFFFF_8000_0000_0000..0xFFFF_B000_0000_0000: non-paged pool
//! 0xFFFF_B000_0000_0000..0xFFFF_F000_0000_0000: paged pool
//! 0xFFFF_FA80_0000_0000..0xFFFF_FB7F_C000_0000: PFMDB
//! 0xFFFF_FB7F_C000_0000..0xFFFF_FB80_0000_0000: PFM bitmap so we dont need to alloc for literally everything
//! 0xFFFF_FB80_0000_0000..0xFFFF_FC00_0000_0000: page tables (recursive map with index 0o767/0x1F7)
//! 0xFFFF_FC00_0000_0000..0xFFFF_FC80_0000_0000: system PTE pool (used for phys/mmio mapping and temporary access)
//! 0xFFFF_FC80_0000_0000..0xFFFF_FCFF_C000_0000: kernel stacks
//! 0xFFFF_FCFF_C000_0000..0xFFFF_FD00_0000_0000: per-core data
//! 0xFFFF_FD00_0000_0000..0xFFFF_FF00_0000_0000: framebuffers
//! 0xFFFF_FFFF_8000_0000..0xFFFF_FFFF_FFFF_F000: kernel image (location derived from bootloader behavior)

const pfmdb = @import("pfmdb.zig");
const pte = @import("pte.zig");
const std = @import("std");
const util = @import("util");

inline fn entry_index(addr: usize, level: usize) usize {
    const ptes_per_table_bits = comptime std.math.log2(std.mem.page_size / @sizeOf(pte.PresentPte));
    const shift = std.math.log2(std.mem.page_size) + (ptes_per_table_bits * (level - 1));
    const mask = (@as(usize, 1) << (48 - shift)) - 1;
    return (addr >> shift) & mask;
}

pub const pfm_db_addr: usize = 0xFFFF_FA80_0000_0000;
pub const pfm_map_tracking_addr: usize = pfm_db_addr + (0o777 << 30);

pub const pte_recurse_index: u9 = 0o767;
pub const pte_base_addr: usize = util.signExtendBits(usize, 12 + (9 * 4), @as(usize, pte_recurse_index) << (12 + 9 * 3));
pub const pde_base_addr: usize = pte_base_addr + (@as(usize, pte_recurse_index) << (12 + 9 * 2));
pub const ppe_base_addr: usize = pde_base_addr + (@as(usize, pte_recurse_index) << (12 + 9 * 1));
pub const pxe_base_addr: usize = ppe_base_addr + (@as(usize, pte_recurse_index) << (12 + 9 * 0));

pub const pxe_selfmap_addr = pxe_base_addr + (@as(usize, pte_recurse_index) * @sizeOf(pte.Pte));

comptime {
    std.testing.expectEqual(0o177777_767_000_000_000_0000, pte_base_addr) catch unreachable;
    std.testing.expectEqual(0o177777_767_767_000_000_0000, pde_base_addr) catch unreachable;
    std.testing.expectEqual(0o177777_767_767_767_000_0000, ppe_base_addr) catch unreachable;
    std.testing.expectEqual(0o177777_767_767_767_767_0000, pxe_base_addr) catch unreachable;
    std.testing.expectEqual(0o177777_767_767_767_767_7670, pxe_selfmap_addr) catch unreachable;
}

pub const pte_base: [*]pte.Pte = @ptrFromInt(pte_base_addr);
pub const pde_base: [*]pte.Pte = @ptrFromInt(pde_base_addr);
pub const ppe_base: [*]pte.Pte = @ptrFromInt(ppe_base_addr);
pub const pxe_base: [*]pte.Pte = @ptrFromInt(pxe_base_addr);
pub const pxe_selfmap: *pte.Pte = @ptrFromInt(pxe_selfmap_addr);

pub const syspte_space: [*]pte.Pte = @ptrCast(pte_from_addr(0xFFFF_FC00_0000_0000));

pub const prcbs: [*]@import("../../smp.zig").LcbWrapper = @ptrFromInt(0xFFFF_FCFF_C000_0000);

pub fn pte_from_addr(addr: usize) *pte.Pte {
    return &pte_base[entry_index(addr, 1)];
}

/// get the address of the page pointed to by this PTE
pub fn addr_from_pte(e: *const pte.Pte) *align(4096) [4096]u8 {
    return @ptrFromInt(@as(usize, @bitCast((@as(isize, @bitCast(@intFromPtr(e))) << 25) >> 16)));
}

pub fn pde_from_addr(addr: usize) *pte.Pte {
    return &pde_base[entry_index(addr, 2)];
}

/// get the address of the page pointed to by this PDE
/// BE AWARE this is NOT the page table the pde points to directly, this is the ACTUAL PAGE
pub fn addr_from_pde(e: *const pte.Pte) *align(4096) [4096]u8 {
    return @ptrFromInt(@as(usize, @bitCast((@as(isize, @bitCast(@intFromPtr(e))) << 34) >> 16)));
}

pub fn ppe_from_addr(addr: usize) *pte.Pte {
    return &ppe_base[entry_index(addr, 3)];
}

/// get the address of the page pointed to by this PPE
/// BE AWARE this is NOT the page directory the ppe points to directly, this is the ACTUAL PAGE
pub fn addr_from_ppe(e: *const pte.Pte) *align(4096) [4096]u8 {
    return @ptrFromInt(@as(usize, @bitCast((@as(isize, @bitCast(@intFromPtr(e))) << 43) >> 16)));
}

pub fn pxe_from_addr(addr: usize) *pte.Pte {
    return &pxe_base[entry_index(addr, 4)];
}

/// get the address of the page pointed to by this PXE
/// BE AWARE this is NOT the page directory table the pxe points to directly, this is the ACTUAL PAGE
pub fn addr_from_pxe(e: *const pte.Pte) *align(4096) [4096]u8 {
    return @ptrFromInt(@as(usize, @bitCast((@as(isize, @bitCast(@intFromPtr(e))) << 52) >> 16)));
}

pub fn pfi_from_pte(p: *const pte.Pte) ?pfmdb.Pfi {
    return if(p.unknown.present) p.valid.addr.pfi else null;
}