//! pool support for kernel objects where `sizeof(T) < page_size / 2`
//! the globals in this file manage pool pages, including expanding the pool,
//! and a global GeneralPurposeAllocator is provided backed by the pool pages
//!
//! the pool space is based at virtual address 0o177777_740_000_000_000_0000

const mm = @import("mm.zig");
const pfmdb = @import("pfmdb.zig");
const map = @import("map.zig");
const std = @import("std");
const collections = @import("collections");
const queue = collections.queue;

const hal = @import("../hal.zig");
const SpinLock = hal.SpinLock;

const assert = std.debug.assert;

const Pfi = pfmdb.Pfi;

var lock: SpinLock = .{};

var single_free_pages: queue.SequencedList = .empty;

const pool_base: Pfi = 0o740_000_000_000;
const pxe: u9 = @truncate(pool_base >> 27);

var next_page: mm.PfiBreakdown = .{ .pfi = pool_base };
var pdes_mapped: u27 = next_page.pde_breakdown.pde;
var ppes_mapped: u18 = next_page.ppe_breakdown.ppe;

fn reserve_ppe() !void {
    assert(next_page.ppe_breakdown.ppe > ppes_mapped);

    assert(!map.ppe_base[ppes_mapped].unknown.present);

    mm.valid_pte.valid.addr.pfi = try pfmdb.alloc_page_undefined();
    map.ppe_base[ppes_mapped] = mm.valid_pte;
    @memset(map.addr_from_pte(&map.ppe_base[ppes_mapped]), 0);

    ppes_mapped += 1;
}

fn reserve_pde() !void {
    if (next_page.ppe_breakdown.ppe > ppes_mapped) {
        try reserve_ppe();
    }
    assert(pdes_mapped < next_page.pde_breakdown.pde);
    assert(!map.pde_base[pdes_mapped].unknown.present);

    mm.valid_pte.valid.addr.pfi = try pfmdb.alloc_page_undefined();
    map.pde_base[pdes_mapped] = mm.valid_pte;
    @memset(map.addr_from_pte(&map.pde_base[pdes_mapped]), 0);

    pdes_mapped += 1;
}

const pages_per_reservation = 0x80;

fn reserve_pages() !void {
    if (next_page.breakdown.pxe != pxe) {
        return error.OutOfMemory;
    }
    if (next_page.pde_breakdown.pde > pdes_mapped) {
        try reserve_pde();
    }

    for (0..pages_per_reservation) |_| {
        assert(!map.pte_base[next_page.pfi].unknown.present);

        mm.valid_pte.valid.addr.pfi = try pfmdb.alloc_page_undefined();
        map.pte_base[next_page.pfi] = mm.valid_pte;

        const page = map.addr_from_pte(&map.pte_base[next_page.pfi]);
        @memset(page, 0);

        const entry: *queue.SinglyLinkedNode = @ptrCast(page);
        single_free_pages.push(entry);

        next_page.pfi += 1;
    }
}

fn alloc_page() !*align(4096) [4096]u8 {
    if (single_free_pages.pop()) |node| {
        @branchHint(.likely);
        return @alignCast(@ptrCast(node));
    }

    const iflag = lock.lock_cli();
    defer lock.unlock_sti(iflag);

    // loop until we get a page or an error
    while (true) {
        // try getting a page before expanding just in case someone else did it between fast-path and lock
        if (single_free_pages.pop()) |node| {
            @branchHint(.unpredictable);
            return @alignCast(@ptrCast(node));
        }

        // and reserve pages. this reserves multiple pages at once (count tunable for perf later)
        try reserve_pages();
    }
}

fn free_page(page: *align(4096) [4096]u8) void {
    single_free_pages.push(@ptrCast(page));
}

fn alloc_impl(_: *anyopaque, len: usize, _: u8, _: usize) ?[*]u8 {
    if (len > std.mem.page_size) return null;
    return @ptrCast(alloc_page() catch return null);
}

fn resize_impl(_: *anyopaque, _: []u8, _: u8, _: usize, _: usize) bool {
    return false;
}

fn free_impl(_: *anyopaque, buf: []u8, _: u8, _: usize) void {
    free_page(@alignCast(@ptrCast(buf.ptr)));
}

const pool_page_vtable: std.mem.Allocator.VTable = .{
    .alloc = alloc_impl,
    .resize = resize_impl,
    .free = free_impl,
};

const pool_page_allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &pool_page_vtable,
};

const pool_gpa: std.heap.GeneralPurposeAllocator(.{
    .MutexType = @import("../../std_shims/spin_lock_mutex_impls.zig").HighSpinLockMutex,
}) = .{
    .backing_allocator = pool_page_allocator,
    .bucket_node_pool = .init(pool_page_allocator),
};

pub const pool_allocator = pool_gpa.allocator();
