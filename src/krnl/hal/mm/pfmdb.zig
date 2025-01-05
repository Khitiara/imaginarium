const std = @import("std");
const cmn = @import("cmn");
const pte = @import("pte.zig");
const hal = @import("../hal.zig");
const map = @import("map.zig");

const MaxSupportedPhysAddrWidth = 48;
pub const PageOffsetBits = std.math.log2_int(usize, std.mem.page_size);
pub const PageBitsPerPageLevel = 9;
pub const LargePageOffsetBits = PageOffsetBits + PageBitsPerPageLevel;
pub const HugePageOffsetBits = LargePageOffsetBits + PageBitsPerPageLevel;
pub const PageOffset: type = std.meta.Int(.unsigned, PageOffsetBits);
pub const Pfi: type = std.meta.Int(.unsigned, MaxSupportedPhysAddrWidth - PageOffsetBits);

test "bit widths" {
    const testing = std.testing;
    switch (@import("builtin").cpu.arch) {
        .x86_64 => {
            try testing.expectEqual(12, PageOffsetBits);
            try testing.expectEqual(36, @bitSizeOf(Pfi));
        },
        else => {},
    }
}

comptime {
    _ = Pfm;
}

pub var free_list: PfmList = .{ .associated_status = .free_list };
pub var zero_list: PfmList = .{ .associated_status = .zero_list };

pub const pfm_db: [*]Pfm = @ptrFromInt(map.pfm_db_addr);
const pfm_db_bitmap: [*]usize = @ptrFromInt(map.pfm_map_tracking_addr);

pub var pfm_bitmap: std.DynamicBitSetUnmanaged = .{
    .masks = pfm_db_bitmap,
};

pub inline fn pfm_for_pfi(pfi: Pfi) ?*Pfm {
    if (pfi >= pfm_bitmap.bit_length) return null;
    if (!pfm_bitmap.isSet(pfi)) return null;
    return &pfm_db[pfi];
}

pub const PfmStatus = enum(u3) {
    /// the page is not usable for general-purpose memory
    invalid,
    /// the page is currently mapped. _2.index is valid, _3.share_count is valid,
    /// and _0.pte points to a present PTE mapping this page to virtual memory.
    /// when refcount hits 0, this page may be moved to either the writeback_pending
    /// or standby lists if it is dirty or clean respectively. refcount is only
    /// directly managed or checked for pages allocated from paged pool
    mapped,
    /// the page is unmapped without free due to lack of use but its former
    /// contents are still present in physical memory. _0.pte points to a transition
    /// PTE formerly mapping this page to virtual memory. a page fault to the
    /// transition PTE can be resolved by removing this page from the standby list
    /// and re-mapping it.
    standby_list,
    /// the page is free but has undefined contents, and may be unsuitable
    /// for secure allocations but may be suitable for mapping a view of a file
    /// and may eventually be zeroed by the zero page thread
    free_list,
    /// the page has been filled with zeroes and is suitable for any allocation.
    /// if the contents of the page before allocation are guaranteed not to be
    /// accessed by allocating code then free_list should be prioritized
    zero_list,
    /// the page is unmapped without free but has been modified and
    /// must be written to swap before the page contents can be freed for future
    /// allocations. _0.pte points to a transition PTE formerly mapping this page
    /// to virtual memory. a page in this state is moved to the standby list when
    /// the swap writeback is completed, unless the page's reference count is
    /// above 0 in which case it is transitioned back to the mapped state.
    writeback_pending_list,
    /// the page is currently waiting on paging IO, either to readback a swapped or
    /// file-mapped page or because the writeback thread dequeued this page from the
    /// writeback list. _2.io_evt points to an event which will be signalled
    /// when the io is completed, AFTER the page is transitioned to either standby or
    /// a valid mapped state. the thread which initiated io is responsible for
    /// allocating and freeing the event, and any other thread which faults the same
    /// page MUST wait on that event and re-check the fault condition.
    paging_io_in_progress,
};

pub const PfmList = struct {
    first: Pfi = terminator,
    last: Pfi = terminator,
    count: usize = 0,
    associated_status: PfmStatus,
    lock: hal.QueuedSpinLock = .{},

    pub const terminator: Pfi = std.math.maxInt(Pfi);

    pub fn push(self: *PfmList, pfi: Pfi) void {
        // TODO: locking
        self.count += 1;
        const pfm = &pfm_db[pfi];
        pfm._1.status = self.associated_status;
        pfm._3.flink.next = terminator;
        if (self.last != terminator) {
            pfm._2.blink.prev = self.last;
            pfm_db[self.last]._3.flink.next = pfi;
        } else {
            std.debug.assert(self.first == terminator);
            self.first = pfi;
        }
        self.last = pfi;
    }

    pub fn pop_internal(self: *PfmList) Pfi {
        // TODO: locking
        const pfi = self.first;
        remove_internal(self, pfi);
        return pfi;
    }

    pub fn remove_internal(self: *PfmList, pfi: Pfi) void {
        // TODO: locking
        self.count -= 1;
        const pfm = &pfm_db[pfi];
        const prev = pfm._2.blink.prev;
        const next = pfm._3.flink.next;
        if (prev != terminator) {
            const p = &pfm_db[prev];
            p._3.flink.next = next;
        } else {
            std.debug.assert(self.first == pfi);
            self.first = next;
        }
        if (next != terminator) {
            const n = &pfm_db[next];
            n._2.blink.prev = prev;
        } else {
            std.debug.assert(self.last == pfi);
            self.last = prev;
        }
    }
};

pub const PfmPageSize = enum(u2) {
    /// 4k
    small,
    /// 2m
    large,
    /// 1g
    huge,
};

/// Physical Page Metadata
pub const Pfm = extern struct {
    _0: packed union {
        /// a pointer to the page table entry pointing to this physical page.
        /// if this physical page is currently mapped as part of a large page,
        /// this PTE will point back to an early physical page (rounding the
        /// index of this PFM down to a multiple of either 512 or 262144 for
        /// large and huge pages respectively on x86_64.)
        pte: ?*pte.Pte,
        /// as the pte pointer must be aligned to a usize boundary, we are
        /// guaranteed 2 or 3 free bits on 32- and 64-bit targets respectively.
        /// the lowest of those free bits is used as a lock bit for an atomic
        /// bts operation equivalent to an embedded spinlock.
        lock: packed struct(usize) {
            lock_bit: u1,
            _: std.meta.Int(.unsigned, @bitSizeOf(usize) - 1),
        },
    },
    _1: packed struct(usize) {
        /// the size of the virtual page
        page_size: PfmPageSize,
        /// the general page status, indicating also which list the page is in if any
        status: PfmStatus,
        /// the page frame index of the table containing the page table entry
        /// which maps or refers to this page
        pte_table_pfi: Pfi,
        // reserve these bits to maybe support 52-bit phys addrs later
        _pad: std.meta.Int(.unsigned, 40 - @bitSizeOf(Pfi)) = 0,
        /// the memory type index in the PAT register, if applicable
        pat_index: u3,
        /// number of general io operations fixing this page plus an additional 1 if
        /// share_count is greater than 0.
        refcnt: u16,
    },
    _2: packed union {
        blink: packed struct(usize) {
            /// the index of the previous page in whichever list this page is part of.
            prev: Pfi,
            // reserve these bits to maybe support 52-bit phys addrs later
            _pad: std.meta.Int(.unsigned, 40 - @bitSizeOf(Pfi)) = 0,
            _: u24 = 0,
        },
        /// the index in the virtual memory working set of the block including this page.
        /// all bits set = nonpaged allocation
        index: usize,
        /// an event to be signaled when IO to resolve a fault on this page is completed
        io_evt: *@import("../../thread/Event.zig"),
    },
    _3: packed union {
        flink: packed struct(usize) {
            /// the index of the next page in whichever list this page is part of
            next: Pfi,
            // reserve these bits to maybe support 52-bit phys addrs later
            _pad: std.meta.Int(.unsigned, 40 - @bitSizeOf(Pfi)) = 0,
            _: u24 = 0,
        },
        share_count: usize,
    },

    pub fn init_unusable() Pfm {
        return Pfm{
            ._0 = .{ .pte = null },
            ._1 = .{
                .page_size = .small,
                .status = .unsuitable_for_general_purpose,
                .pte_table_pfi = 0,
                .pat_index = 0,
                .refcnt = 0,
            },
            ._2 = .{
                .index = 0,
            },
            ._3 = .{
                .share_count = 0,
            },
        };
    }
};

inline fn compute_end_pfi(entry: *const cmn.memmap.Entry) Pfi {
    return @intCast((@intFromEnum(entry.base) + entry.size) >> PageOffsetBits);
}

pub fn bootstrap_pfmdb(pfns: []Pfm, memmap: []cmn.memmap.Entry) Pfi {
    var index: Pfi = 0;
    outer: for (memmap) |*entry| {
        const base_pfi = std.mem.alignForwardLog2(@intFromEnum(entry.base), PageOffsetBits) >> PageOffsetBits;
        const end_pfi = compute_end_pfi(entry);
        while (index < base_pfi) : (index += 1) {
            if (index >= pfns.len) break :outer;
            pfns[index] = .init_unusable();
        }
        while (index < end_pfi) : (index += 1) {
            if (index >= pfns.len) break :outer;
            switch (entry.type) {
                .normal => Pfm.init_free(index, pfns.ptr),
                else => pfns[index] = .init_unusable(),
            }
        }
    }
    while (index < pfns.len) : (index += 1) {
        pfns[index] = .init_unusable();
    }
    return index;
}

pub fn bootstrap_mark_allocated(pfns: []Pfm, start: Pfi, end: Pfi) void {
    for (pfns[start..end], start..) |*pfm, pfi| {
        pfm._2.index = std.math.maxInt(usize);
        if (pfm._1.status == .free_list) {
            free_list.remove_internal(pfi, pfns.*);
        }
        if (pfm._1.status == .unsuitable_for_general_purpose) {
            pfm._1.status = .mapped_for_system_io;
        } else {
            pfm._1.status = .mapped;
        }
    }
}
