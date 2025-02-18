//! the kernel memory manager

pub const mminit = @import("mminit.zig");
pub const pool = @import("pool.zig");
pub const syspte = @import("syspte.zig");

pub const map = @import("map.zig");
const pte = @import("pte.zig");
pub const paging = @import("paging.zig");

const std = @import("std");
const arch = @import("../arch/arch.zig");
const Pfi = @import("pfmdb.zig").Pfi;
const cmn = @import("cmn");
const PhysAddr = cmn.types.PhysAddr;

pub const PageAddrFormatter = packed struct(usize) {
    offset: u12,
    p1: u9,
    p2: u9,
    p3: u9,
    p4: u9,
    top: u16,

    pub fn format(self: *const @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{o:0>6}:{o:0>3}:{o:0>3}:{o:0>3}:{o:0>3}:{o:0>4}", .{ self.top, self.p4, self.p3, self.p2, self.p1, self.offset });
    }
};

pub inline fn fmt_paging_addr(addr: usize) PageAddrFormatter {
    return @bitCast(addr);
}

pub inline fn pages_spanned(start: usize, len: usize) usize {
    return std.math.divCeil(usize, (start & comptime (std.heap.pageSize() - 1)) + len, std.heap.pageSize()) catch unreachable;
}

pub inline fn flush_local_tlb() void {
    arch.control_registers.write(.cr3, arch.control_registers.read(.cr3));
}

pub const PfiBreakdown = packed union { pfi: Pfi, breakdown: packed struct(Pfi) {
    pte: u9,
    pde: u9,
    ppe: u9,
    pxe: u9,
}, pde_breakdown: packed struct(Pfi) {
    pte: u9,
    pde: u27,
}, ppe_breakdown: packed struct(Pfi) {
    pte: u9,
    pde: u9,
    ppe: u18,
} };

pub var valid_pte: @import("pte.zig").Pte = .{
    .valid = .{
        .writable = true,
        .user_mode = false,
        .write_through = false,
        .cache_disable = false,
        .pat_size = false,
        .global = false,
        .copy_on_write = false,
        .sw_dirty = false,
        .addr = .{ .pfi = 0 },
        .pk = 0,
        .xd = false,
    },
};

pub var io_pte: @import("pte.zig").Pte = .{
    .valid = .{
        .writable = true,
        .user_mode = false,
        .write_through = true,
        .cache_disable = false,
        .pat_size = false,
        .global = false,
        .copy_on_write = false,
        .sw_dirty = false,
        .addr = .{ .pfi = 0 },
        .pk = 0,
        .xd = false,
    },
};

pub noinline fn map_io(physaddr: PhysAddr, len: usize, cache_type: paging.MemoryCacheType) ![]u8 {
    const pages = pages_spanned(@intFromEnum(physaddr), len);
    const cache_bits: paging.PATBits = .{ .typ = cache_type };
    var tmp_pte = io_pte;
    tmp_pte.valid.write_through = cache_bits.bits.pwt;
    tmp_pte.valid.cache_disable = cache_bits.bits.pcd;
    tmp_pte.valid.pat_size = cache_bits.bits.pat;

    const ptes = syspte.reserve(@intCast(pages)) orelse return error.OutOfMemory;
    for (ptes, physaddr.page()..) |*p, page| {
        tmp_pte.valid.addr.pfi = @truncate(page);
        p.* = tmp_pte;
    }

    const block = @as([*]u8, @ptrCast(map.addr_from_pte(&ptes[0])))[@intFromEnum(physaddr) & 0xFFF ..][0..len];

    // std.log.debug("mapping {x}[0..{x}] for io ({d} pages) to block {*}", .{ @intFromEnum(physaddr), len, pages, block });
    flush_local_tlb();
    return block;
}

pub fn unmap_io(slc: []u8) void {
    const back = std.mem.alignBackward(usize, @intFromPtr(slc.ptr), 4096);
    const pages = pages_spanned(@intFromPtr(slc.ptr), slc.len);
    // std.log.debug("unmapping {*} ({d} pages)", .{ slc, pages });
    const ptes = @as([*]pte.Pte, @ptrCast(map.pte_from_addr(back)))[0..pages];

    syspte.release(ptes);
    flush_local_tlb();
}
