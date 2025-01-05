//! System PTE pool, that is to say a region of pages whose PTEs default to storing a free block list.
//! This is heavily inspired by reactos's implementation of the syspte system from the windows NT kernel.
//!
//! Accessing the actual list can be done easily using the recursive page mappings (index 0x1F7/0o767).
//! The first free entry is stored in a global variable as an optional pointer, as is the number of free pages.
//! The first free page in each block stores a boolean flag indicating if it is the only free page in the block
//! or if it is the first of a larger block. If the singleton flag is unset, the next free page in order stores
//! the block size in its next value.
//!
//! The free list SHOULD be kept sorted in ascending order of block length.

const pte = @import("pte.zig");
const Pte = pte.Pte;
const Pfi = @import("pfmdb.zig").Pfi;
const map = @import("map.zig");
const mm = @import("mm.zig");
const std = @import("std");

const QueuedSpinLock = @import("../QueuedSpinLock.zig");

var first: Pte = undefined;
var free_count: u32 = undefined;
var total_ptes: u32 = undefined;

var syspte_lock: QueuedSpinLock = .{};

inline fn get_cluster_size(p: [*]Pte) u32 {
    if (p.list.singleton) {
        return 1;
    } else {
        return p[1].list.next;
    }
}

inline fn get_next(p: [*]Pte) ?[*]Pte {
    switch (p.list.next) {
        std.math.maxInt(u32) => return null,
        else => |i| return i,
    }
}

inline fn set_cluster_size(p: [*]Pte, s: u32) void {
    if (s == 1) {
        if (get_cluster_size(p) != 1) {
            p[1] = .{ .int = 0 };
        }
        p.list.singleton = true;
    } else {
        p.list.singleton = false;
        p[1].int = 0;
        p[1].list.next = s;
    }
}

inline fn get_index(p: [*]Pte) u32 {
    return @intCast(p - map.syspte_space);
}

/// initialize system pte space with a block of PTEs. these should be pointed by the recursive page table
/// so the pointer arithmetic works out here. this function set the free list to a single block containing
/// all of the ptes. the reserve function handles splitting the block as needed and the release function
/// can re-merge blocks too so this should be fine generally speaking.
pub fn init(ptes: []Pte) void {
    var tok: QueuedSpinLock.Token = undefined;
    syspte_lock.lock(&tok);
    defer tok.unlock();

    @memset(ptes, .{ .int = 0 });
    free_count = @intCast(ptes.len);
    if (ptes.len == 0) {
        @branchHint(.cold);
        first = .{
            .list = .{
                .singleton = false,
                .next = std.math.maxInt(u32),
            },
        };
        return;
    }
    first = .{
        .list = .{
            .singleton = false,
            .next = ptes.ptr - map.syspte_space,
        },
    };
    ptes[0] = .{
        .list = .{
            .singleton = ptes.len == 1,
            .next = std.math.maxInt(u32),
        },
    };
    if (ptes.len == 1) {
        @branchHint(.unlikely);
        return;
    }
    ptes[1] = .{
        .list = .{
            .singleton = false,
            .next = free_count,
        },
    };
    total_ptes = free_count;
}

/// reserve `count` contiguous pages from system pte space. returns a slice of PTEs on success
/// or null if there is no sufficiently large block of PTEs.
///
/// this function handles splitting large blocks of PTEs as needed to reserve space.
pub fn reserve(count: usize) ?[]Pte {
    var tok: QueuedSpinLock.Token = undefined;
    syspte_lock.lock(&tok);
    defer tok.unlock();

    var prev: [*]Pte = &first;
    const cluster, var cluster_size: u32 = while (get_next(prev)) |cluster| {
        const sz = get_cluster_size(cluster);
        // if the block is big enough then break. there wont be a better candidate because
        // the free block list is sorted in ascending order of size.
        if (sz >= count) break .{ cluster, sz };
        prev = cluster;
    } else {
        return null;
    };

    // unlink
    prev.list.next = cluster.list.next;

    defer {
        free_count -= count;
        // only release needs a shootdown, and these are expected to be mainly local-use overall
        mm.flush_local_tlb();
    }

    if (cluster_size == count) {
        // if the block is an exact match then just return it.
        const ret: [*]Pte = @ptrCast(cluster);
        @memset(ret[0..@max(2, count)], .{ .int = 0 });
        return ret[0..count];
    } else {
        // otherwise we need to split the block in two.
        // we take new allocation from the end of the block to try and minimize
        // the chances of multiple re-mergings in release. IDK how well this will
        // actually work or what difference thatll make though.
        const idx: u32 = get_index(cluster) + count;
        cluster_size -= count;

        const ret: [*]Pte = map.syspte_space + cluster_size;
        @memset(ret[0..@max(2, count)], .{ .int = 0 });

        // shrink the current cluster
        set_cluster_size(cluster, cluster_size);

        // and we need to find the insert point for the rest of the block.
        // as the block was already in the list it must not be contiguous with any
        // other block in the free list (maintained by the release function)
        // so we dont need to do that check so we just break at the first block
        // at least as big as this one, which means prev will then be the last
        // block smaller than this one, so thats where we insert
        prev = &first;
        while (get_next(prev)) |ib| {
            if (cluster_size <= get_cluster_size(ib)) break;
            prev = ib;
        }

        // and link it in
        cluster.list.next = prev.list.next;
        prev.list.next = idx;

        return ret[0..count];
    }
}

/// return a contiguous slice of PTEs to the system pte pool.
///
/// this function handles merging adjacent/contiguous blocks of PTEs as may
/// be created by returning split chunks of the larger initial block.
pub fn release(ptes: []Pte) void {
    var tok: QueuedSpinLock.Token = undefined;
    syspte_lock.lock(&tok);
    defer tok.unlock();

    @memset(ptes, .{ .int = 0 });

    var count: u32 = @intCast(ptes.len);
    var start: [*]Pte = ptes.ptr;

    free_count += count;

    var prev: [*]Pte = &first;
    var insert: ?[*]Pte = null;
    while (get_next(prev)) |block| {
        const sz = get_cluster_size(block);
        // found block is contiguous with the block to release, so merge them
        if (block + sz == start or start + sz == block) {
            count += sz;
            // move start back if needed
            if (@intFromPtr(block) < @intFromPtr(start)) {
                start = block;
            }

            // unlink
            prev[0].list.next = block.list.next;
            // clear metadata
            @memset(block[0..@max(2, sz)], .{ .int = 0 });
            // and we gotta re-iterate now
            insert = null;
            prev = &first;
        } else {
            // if block is a candidate for first-block-after-new-freed-block then save the previous
            // as a candidate for last-block-before-new-freed-block.
            // if something is saved already then theres a smaller block that is bigger than the
            // one we're freeing so we arent the first after the new
            if (insert == null and count <= sz) {
                insert = prev;
            }
            // even if we are now past the insertion point we keep iterating in case we find a
            // contiguous block so we dont end up with syspte space being super fragmented.
            prev = block;
        }
    }
    if (insert == null) {
        insert = prev;
    }

    set_cluster_size(start, count);
    start.list.next = insert.list.next;
    insert.list.next = get_index(start);
}
