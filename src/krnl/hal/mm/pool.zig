//! nonpaged space page allocator
//! implemented as a buddy allocator inspired by the one in the linux kernel,
//! but for virtual rather than physical pages. the PFM share_count of the
//! corresponding physical pages are used for determining if a page is free
//! or not in the buddy system.

const queue = @import("collections").queue;
const map = @import("map.zig");
const pfmdb = @import("pfmdb.zig");
const std = @import("std");
const mm = @import("mm.zig");
const pte = @import("pte.zig");
const Pte = pte.Pte;

const SpinLock = @import("../hal.zig").SpinLock;

const base_addr: usize = 0xFFFF_8000_0000_0000;
const base: [*][4096]u8 = @ptrFromInt(base_addr);

// const pmm_sizes_global = blk: {
//     var sizes: [18]usize = [_]usize{0} ** 18;
//     for (base_root_shift..30, 0..) |shift, i| {
//         sizes[i] = 1 << shift;
//     }
//     break :blk sizes;
// };

const BuddyList = queue.DoublyLinkedList(Buddy, "hook");

const Buddy = struct {
    hook: queue.DoublyLinkedNode,
    order: u8,
};

const Root = struct {
    comptime size: usize = 0,
    frees: BuddyList,
};

const base_root_shift = 12;
const roots_count = 10;

var roots = b: {
    var sizes: [roots_count]usize = [_]usize{0} ** roots_count;
    for (0..roots_count, base_root_shift..) |i, shift| {
        sizes[i] = 1 << shift;
    }

    const szs = sizes;

    var tmp: [szs.len]Root = undefined;
    for (szs, 0..) |sz, i| {
        tmp[i] = .{ .size = sz, .frees = .{} };
    }
    const tmp2 = tmp;
    break :b tmp2;
};

var lock: SpinLock = .{};

inline fn buddy_for(addr: usize, order: usize) usize {
    // @setRuntimeSafety(false);
    return addr ^ (@as(usize, 1) << @intCast(order + base_root_shift));
}

inline fn primary_for(addr: usize, order: usize) usize {
    // @setRuntimeSafety(false);
    return addr & ~(@as(usize, 1) << @intCast(order + base_root_shift));
}

inline fn order_for(size: usize) u8 {
    return std.math.log2_int_ceil(usize, size) -| base_root_shift;
}

inline fn is_free(ptr: anytype) bool {
    const pfi = map.pfi_from_pte(map.pte_from_addr(@intFromPtr(ptr))) orelse return false;
    return pfmdb.pfm_db[pfi]._3.share_count == 0;
}

/// free a block with a given order. assumes all lower orders are already free.
/// in the process, the given block is coalesced as much as possible.
fn free_page_order(pg: *anyopaque, order: u8) void {
    // mark the page as free using pfm.share_count
    const pfi = map.pfi_from_pte(map.pte_from_addr(@intFromPtr(pg))) orelse @panic("could not find pfi for nonpaged pool PTE");
    pfmdb.pfm_db[pfi]._3.share_count = 0;

    // cast the pointer and clean out the buddy metadata
    var header: *Buddy = @alignCast(@ptrCast(pg));
    header.hook = .{};
    header.order = order;

    // coalesce iteratively, overwriting header with the primary buddy of a pair at an order
    // the loop stops if theres no higher orders to coalesce to
    while (header.order < roots.len - 1) {
        // get the buddy at this order
        const bud: *Buddy = @ptrFromInt(buddy_for(@intFromPtr(header), header.order));
        // if the buddy isnt free then we cant coalesce and more so break the loop
        if (!is_free(bud)) break;

        // remove the buddy from a free list because its being coalesced
        roots[bud.order].frees.remove(bud);
        // get the primary buddy for this order, increment order, and iterate
        header = @ptrFromInt(primary_for(@intFromPtr(header), header.order));
        header.order += 1;
    }

    // add the fully coalesced block to the appropriate higher-order free list
    // add front for possible cache optimizations just in case
    roots[header.order].frees.add_front(header);
}

fn free_block(block: []u8) void {
    if (block.len == 0) return;

    const iflg = lock.lock_cli();
    defer lock.unlock_sti(iflg);

    free_page_order(block.ptr, order_for(block.len));
}

var next_ppe: [*]Pte = @ptrCast(map.ppe_from_addr(base_addr));
var next_pde: [*]Pte = @ptrCast(map.pde_from_addr(base_addr));
var pde_idx: u9 = 0;
const ovflw_ppe: u18 = map.entry_index(0xFFFF_B000_0000_0000, 3);

pub noinline fn expand_ppe() void {
    defer next_ppe += 1;

    const pfi = pfmdb.alloc_page_undefined() catch |e| std.debug.panic("out of memory for nonpaged pool expansion! {}", .{e});

    mm.valid_pte.valid.addr.pfi = pfi;
    next_ppe[0] = mm.valid_pte;
    pfmdb.pfm_db[pfi].set_mapped_primary(&next_ppe[0]);

    const pd_pg = map.addr_from_pte(&next_ppe[0]);

    @memset(pd_pg, 0);
}

/// expand the nonpaged pool by one pde (2M on x86_64)
noinline fn expand() ?usize {
    std.log.debug("expanding nonpaged pool!", .{});
    if (next_ppe - map.ppe_base >= ovflw_ppe) {
        return null;
    }

    defer next_pde += 1;

    // std.log.debug("A   {o}", .{mm.fmt_paging_addr(@intFromPtr(next_ppe))});

    var pfi = pfmdb.alloc_page_undefined() catch |e| std.debug.panic("out of memory for nonpaged pool expansion! {}", .{e});

    mm.valid_pte.valid.addr.pfi = pfi;
    next_pde[0] = mm.valid_pte;
    pfmdb.pfm_db[pfi].set_mapped_primary(&next_pde[0]);

    const pt_pg = map.addr_from_pte(&next_pde[0]);

    // std.log.debug("AA  {o} - {x}", .{mm.fmt_paging_addr(@intFromPtr(pd_pg)), pfi});

    @memset(pt_pg, 0);
    const pt: pte.PageTable = @ptrCast(pt_pg);

    for (0..0x200) |ptei| {
        // std.log.debug("AAAA {o} {o} {o}", .{next_ppe - map.ppe_base, pdei, ptei});
        pfi = pfmdb.alloc_page_undefined() catch |e| std.debug.panic("out of memory for nonpaged pool expansion! {}", .{e});
        mm.valid_pte.valid.addr.pfi = pfi;
        pt[ptei] = mm.valid_pte;
        pfmdb.pfm_db[pfi].set_mapped_primary(&pt[ptei]);

        const pg = map.addr_from_pte(&pt[ptei]);
        @memset(pg, 0);
    }

    pde_idx, const ovflw = @addWithOverflow(pde_idx, 1);
    if (ovflw == 1) {
        expand_ppe();
    }

    return @intFromPtr(map.addr_from_pde(&next_pde[0]));
}

/// allocate pages for a block of given order
fn alloc_pages_order(order: u8) ?usize {
    // check the free list first for the fast path
    if (roots[order].frees.remove_front()) |b| {
        // mark as nonfree in pfm.share_count
        const pfi = map.pfi_from_pte(map.pte_from_addr(@intFromPtr(b))) orelse @panic("no PFI for reserved nonpage pool page");
        pfmdb.pfm_db[pfi]._3.share_count = 1;
        return @intFromPtr(b);
    }

    // if we're top order then grab another top-order block from scratch
    if (order == roots.len - 1) {
        const addr = expand() orelse return null;
        // mark as nonfree in pfm.share_count
        const pfi = map.pfi_from_pte(map.pte_from_addr(addr)) orelse @panic("no PFI for reserved nonpage pool page");
        pfmdb.pfm_db[pfi]._3.share_count = 1;
        return addr;
    }

    // we're not top-order and there was nothing in the free list so we have to split
    const primary = alloc_pages_order(order + 1) orelse return null;

    // mark the page as nonfree using pfm.share_count
    const pfi = map.pfi_from_pte(map.pte_from_addr(primary)) orelse @panic("no PFI for reserved nonpage pool page");
    pfmdb.pfm_db[pfi]._3.share_count = 1;

    // split the high level block. the primary bit needs no work since we're returning it again anyway
    // so just grab the buddy and mark it free
    //
    // possible optimization: return the secondary so we need less pfmdb accesses
    const b: *Buddy = @ptrFromInt(buddy_for(primary, order));
    b.order = order;
    // std.log.debug("freeing split buddy of order {d}", .{order});

    // mark free in pfm.share_count
    const pfi2 = map.pfi_from_pte(map.pte_from_addr(@intFromPtr(b))) orelse @panic("no PFI for reserved nonpage pool page");
    pfmdb.pfm_db[pfi2]._3.share_count = 0;

    // and add the secondary buddy to the free list
    roots[order].frees.add_front(b);

    return primary;
}

/// allocate a block of given size (rounded up to a power-of-two number of pages.
/// use a GPA or slab etc if sub-page allocations are needed
fn alloc_block(size: usize) ?[*]u8 {
    if (size == 0) return @ptrFromInt(std.math.maxInt(usize));

    const iflg = lock.lock_cli();
    defer lock.unlock_sti(iflg);

    const order = order_for(size);
    if (order > roots.len) return null;
    const addr = alloc_pages_order(order) orelse return null;

    return @as([*]u8, @ptrFromInt(addr));
}

fn alloc_impl(_: *anyopaque, len: usize, _: std.mem.Alignment, _: usize) ?[*]u8 {
    return alloc_block(len);
}

fn resize_impl(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
    return false;
}

fn free_impl(_: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
    free_block(buf);
}

fn remap_impl(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
    return null;
}

const pool_page_vtable: std.mem.Allocator.VTable = .{
    .alloc = alloc_impl,
    .resize = resize_impl,
    .free = free_impl,
    .remap = remap_impl,
};

pub const pool_page_allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &pool_page_vtable,
};

var pool_gpa: std.heap.GeneralPurposeAllocator(.{
    .MutexType = @import("../../std_shims/spin_lock_mutex_impls.zig").HighSpinLockMutex,
}) = .{
    .backing_allocator = pool_page_allocator,
};

pub const pool_allocator = pool_gpa.allocator();
