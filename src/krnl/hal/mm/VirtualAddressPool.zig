const collections = @import("collections");
const tree = collections.tree;
const TreeNode = tree.TreeNode;
const Pfi = @import("pfmdb.zig").Pfi;
const std = @import("std");
const Order = std.math.Order;
const mm = @import("mm.zig");
const assert = std.debug.assert;

const pool = @import("pool.zig");

const VirtualAddressPool = @This();

pub const VirtualAddressBlock = struct {
    /// avl tree support structure
    hook: TreeNode = .{},
    /// the base address of the block
    start_addr: Pfi,
    /// the end address of the block
    end_addr: Pfi,
    /// whether this virtual address block has extra details.
    /// this is true for some but not all types of allocation -
    /// a raw block of virtual addresses in e.g. the mmio mapping
    /// space will have this as false, but e.g. a mapped view of
    /// a file will include the file offset and a pointer back to
    /// the view object.
    long_details: bool = false,
};

const short_block_pool: std.heap.MemoryPool(VirtualAddressBlock) = .init(pool.pool_allocator);
const long_block_pool: std.heap.MemoryPool(VirtualAddressBlockLong) = .init(pool.pool_allocator);

pub const block_pool = struct {
    pub const ResetMode = std.heap.ArenaAllocator.ResetMode;

    pub fn reset(mode: ResetMode) bool {
        return short_block_pool.reset(mode) and long_block_pool.reset(mode);
    }

    pub fn create_short() !*VirtualAddressBlock {
        return try short_block_pool.create();
    }

    pub fn create_long() !*VirtualAddressBlockLong {
        return try long_block_pool.create();
    }

    pub fn destroy(ptr: *VirtualAddressBlock) void {
        if(ptr.long_details) {
            long_block_pool.destroy(@fieldParentPtr("basic", ptr));
        } else {
            short_block_pool.destroy(ptr);
        }
    }
};

pub const VirtualAddressBlockLong = struct {
    basic: VirtualAddressBlock,
    details: VirtualAddressBlockDetails,
};

pub const VirtualAddressBlockDetails = union(enum) {
    private: struct {},
    // section_map: struct {
    //     file_offset: usize,
    // },
};

pub const VirtualAddressBlockTree = tree.AvlTree(VirtualAddressBlock, "hook", struct {
    pub fn cmp(_: @This(), lhs: *const VirtualAddressBlock, rhs: *const VirtualAddressBlock) Order {
        if (lhs.start_addr > rhs.end_addr) return .gt;
        if (rhs.start_addr > lhs.end_addr) return .lt;
        return .eq;
    }
});
const Range = struct {
    s: usize,
    e: usize,
};
const RangeAdapter = struct {
    pub fn cmp(_: @This(), lhs: Range, rhs: *VirtualAddressBlock) Order {
        if (lhs.s > rhs.end_addr) return .gt;
        if (rhs.base_addr > lhs.e) return .lt;
        return .eq;
    }
};

comptime base_address: usize = 0,
comptime top_address: usize = 0,
root: ?*TreeNode,
block_count: usize = 0,

pub const AddrRangeSearchResult = struct {
    base_address: usize,
    parent: ?*VirtualAddressBlock,
    insert_right: bool,
};

/// this is basically just finding a sufficiently large gap in the list of addresses. the difference between this and
/// @find_empty_address_range_top_down is the iteration order and the relative alignment of returned block - the top_down
/// function returns the highest possible address block and this function returns the lowest possible. these functions
/// have a minor optimization in that the iteration also serves to locate the parent of the newly inserted block,
/// along with which child of the parent the new node should be, meaning the iteration in fetch_insert can be skipped
/// and insert_at be used instead.
pub fn find_empty_address_range_bottom_up(self: *VirtualAddressPool, length: usize, alignment: usize) ?AddrRangeSearchResult {
    const pages = std.math.divCeil(usize, length, std.mem.page_size) catch unreachable;
    const pg_align = alignment / std.mem.page_size;
    var low_vpn = std.mem.alignForward(usize, std.math.divCeil(usize, self.base_address, std.mem.page_size) catch unreachable, pg_align);
    if (self.block_count == 0) {
        return .{
            .base_address = low_vpn * std.mem.page_size,
            .parent = null,
            .insert_right = false,
        };
    }
    var node: ?*VirtualAddressBlock = VirtualAddressBlockTree.extreme_in_order(&self.root, -1);
    var old_node: ?*VirtualAddressBlock = null;
    while (node) |n| {
        if (n.start_addr >= low_vpn + pages) {
            if (VirtualAddressBlockTree.left(n)) {
                if (old_node) |prev| {
                    assert(VirtualAddressBlockTree.right(prev) == null);
                    return .{
                        .base_address = low_vpn * std.mem.page_size,
                        .parent = prev,
                        .insert_right = true,
                    };
                } else unreachable;
            } else {
                return .{
                    .base_address = low_vpn * std.mem.page_size,
                    .parent = n,
                    .insert_right = false,
                };
            }
        }

        if (n.end_addr >= low_vpn) {
            low_vpn = std.mem.alignForward(usize, n.end_addr + 1, pg_align);
        }

        old_node = n;
        node = VirtualAddressBlockTree.next(n);
    }

    if (self.top_address / std.mem.page_size >= low_vpn + pages) {
        return .{
            .base_address = low_vpn * std.mem.page_size,
            .parent = old_node,
            .insert_right = true,
        };
    }

    return null;
}

/// this is basically just finding a sufficiently large gap in the list of addresses. the difference between this and
/// @find_empty_address_range_bottom_up is the iteration order and the relative alignment of returned block - this
/// function returns the highest possible address block and the bottom_up function returns the lowest possible.
/// these functions have a minor optimization in that the iteration also serves to locate the parent of the newly
/// inserted block, along with which child of the parent the new node should be, meaning the traversal in fetch_insert
/// can be skipped and insert_at be used instead. (see @insert_block_at)
pub fn find_empty_address_range_top_down(self: *VirtualAddressPool, length: usize, max_addr: usize, alignment: usize) ?AddrRangeSearchResult {
    const pages = std.math.divCeil(usize, length, std.mem.page_size) catch unreachable;
    const pg_align = std.math.divCeil(usize, alignment, std.mem.page_size) catch unreachable;
    assert(max_addr <= self.top_address);

    if (std.mem.alignForward(usize, std.math.divCeil(usize, self.base_address, std.mem.page_size) catch unreachable, pg_align) * std.mem.page_size + length >= max_addr) {
        return null;
    }

    if (self.block_count == 0) {
        return .{
            .base_address = std.mem.alignBackward(usize, self.top_address + 1 - length, alignment),
            .parent = null,
            .insert_right = false,
        };
    }

    var high_vpn = (max_addr + 1) / std.mem.page_size;

    var node: ?*VirtualAddressBlock = VirtualAddressBlockTree.extreme_in_order(&self.root, 1);
    var old_node: ?*VirtualAddressBlock = null;
    while (node) |n| {
        const low_vpn = std.mem.alignForward(usize, n.end_addr + 1, pg_align);
        if (high_vpn > low_vpn and high_vpn - low_vpn >= pages) {
            const base = std.mem.alignBackward(usize, high_vpn - pages, pg_align) * std.mem.page_size;
            if (VirtualAddressBlockTree.right(n)) {
                if (old_node) |prev| {
                    assert(VirtualAddressBlockTree.left(prev) == null);
                    return .{
                        .base_address = base,
                        .parent = prev,
                        .insert_right = false,
                    };
                } else unreachable;
            } else {
                return .{
                    .base_address = base,
                    .parent = n,
                    .insert_right = true,
                };
            }
        }

        if (n.start_addr < high_vpn) {
            high_vpn = n.start_addr;
        }

        old_node = n;
        node = VirtualAddressBlockTree.prev(n);
    }

    const low_vpn = std.mem.alignForward(usize, self.base_address, alignment) / std.mem.page_size;
    if (high_vpn > low_vpn and high_vpn - low_vpn >= pages) {
        return .{
            .base_address = std.mem.alignBackward(usize, high_vpn - pages, pg_align) * std.mem.page_size,
            .parent = old_node,
            .insert_right = false,
        };
    }

    return null;
}

pub const ConflictCheckResult = union(enum) {
    no_conflict: AddrRangeSearchResult,
    conflict: *VirtualAddressBlock,
};

pub fn check_block_conflict(self: *VirtualAddressPool, start_addr: usize, end_addr: usize) ConflictCheckResult {
    if (self.block_count == 0) {
        return .{
            .no_conflict = .{
                .base_address = start_addr,
                .parent = null,
                .insert_right = false,
            },
        };
    }
    const start_page = start_addr / std.mem.page_size;
    const end_page = std.math.divCeil(usize, end_addr, std.mem.page_size) catch unreachable;

    const range: Range = .{ .s = start_page, .e = end_page };
    switch (VirtualAddressBlockTree.lookup_or_insert_position_adapted(&self.root, range, @as(RangeAdapter, undefined))) {
        .found => |n| return .{
            .conflict = n,
        },
        .iunsert_pos => |p| return .{
            .no_conflict = .{
                .base_address = start_addr,
                .parent = p.parent,
                .insert_right = p.right,
            },
        },
    }

    // var node: ?*VirtualAddressBlock = VirtualAddressBlockTree.ref_from_optional_node(self.root);
    // var parent: *VirtualAddressBlock = undefined;
    // assert(node != null);
    // while (node) |n| {
    //     parent = n;
    //     if (n.end_addr < start_page) {
    //         node = VirtualAddressBlockTree.right(n);
    //     } else if (n.start_addr > end_page) {
    //         node = VirtualAddressBlockTree.left(n);
    //     } else {
    //         return .{
    //             .conflict = n,
    //         };
    //     }
    // }
    // return .{
    //     .no_conflict = .{
    //         .base_address = start_addr,
    //         .parent = parent,
    //         .insert_right = start_page > parent.end_addr,
    //     },
    // };
}

/// INTERNAL
///
/// insert a new virtual address block into this pool based on an address range determined from the
/// check_block_conflict or one of the find_empty functions above. the base_address in the info struct can be
/// non-page-aligned in the check_block_conflict case as it is thus user-supplied - the resulting VAB will
/// be page-aligned anyway.
///
/// this function uses AvlTree.insert_at as the empty-range search and overlap detection functions determine the parent
/// and insert direction as part of their tree iterations, thus saving the traversal needed in the normal fetch_insert
/// function on AvlTree.
pub fn insert_block_at(self: *VirtualAddressPool, info: AddrRangeSearchResult, block: *VirtualAddressBlock, length: usize) void {
    block.start_addr = info.base_address / std.mem.page_size;
    block.end_addr = block.start_addr + mm.pages_spanned(info.base_address, length);
    if (info.insert_right) {
        VirtualAddressBlockTree.insert_at(&self.root, info.parent, 1, block);
    } else {
        VirtualAddressBlockTree.insert_at(&self.root, info.parent, -1, block);
    }
}

/// allocate a block of memory from this pool.
///
/// if `base_address` is pointing to a non-null value then an attempt will be made
/// to allocate the block at the desired address, returning `error.ConflictingAddresses`
/// on a failure. if `base_address` is pointing to null then an empty block will be found
/// in the tree by a search. if `boundary` is null, then the search is conducted bottom-up;
/// if `boundary` is non-null then a top-down search is conducted for a block lower in memory
/// than the value of `boundary`. the value of `boundary` is clamped to within the range
/// of addresses managed by this pool, so passing `std.math.maxInt` is sufficient to request
/// a top-down search with no restriction on address.
///
/// regardless of the mode used, if this function returns without error then `base_address` will
/// be filled with the actual base address of the allocated block, which is guaranteed aligned to
/// `alignment`, and `block` will be inserted into the AVL tree and its start and end address
/// fields will be filled.
///
/// the caller is responsible for ensuring that the resultant block of addresses is mapped to
/// physical memory with the desired properties, or that the block has relevant properties
/// set to let the page fault zero resolve demand lazily
pub fn allocate_block(
    self: *VirtualAddressPool,
    block: *VirtualAddressBlock,
    base_address: *?usize,
    length: usize,
    boundary: ?usize,
    alignment: usize,
) !void {
    const search: AddrRangeSearchResult = if (base_address.*) |wanted_addr| w: {
        if (!std.mem.isAligned(wanted_addr, alignment)) {
            return error.WantedAddressNotAligned;
        }
        const end = wanted_addr + length - 1;
        break :w switch (check_block_conflict(self, wanted_addr, end)) {
            .conflict => {
                return error.ConflictingAddresses;
            },
            .no_conflict => |s| s,
        };
    } else b: {
        const s = if (boundary) |tgt_upper| find_empty_address_range_top_down(self, length, @min(tgt_upper, self.top_address), alignment) else find_empty_address_range_bottom_up(self, length, alignment);
        if (s) |s2| {
            base_address.* = s2.base_address;
            assert(s2.base_address > 0);
            if (boundary) |b| {
                assert(s2.base_address + length < b);
            }
            break :b s2;
        }
        return error.OutOfMemory;
    };

    insert_block_at(self, search, block, length);
}
