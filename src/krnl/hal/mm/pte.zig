const std = @import("std");
const pfmdb = @import("pfmdb.zig");

const PtePfiPad = std.meta.Int(.unsigned, 64 - 5 - pfmdb.PageOffsetBits - @bitSizeOf(pfmdb.Pfi));

test "bit widths" {
    const testing = std.testing;
    switch (@import("builtin").cpu.arch) {
        .x86_64 => {
            try testing.expectEqual(11, @bitSizeOf(PtePfiPad));
        },
        else => {},
    }
}

comptime {
    _ = Pte;
}

pub const Pte = packed union {
    unknown: packed struct(u64) {
        /// true if the PTE is a valid mapped page. if this bit is set, hardware directly
        /// accesses the rest of the PTE for use in virtual address translation. if false,
        /// hardware will never directly access the rest of the structure, and the other
        /// fields are used to determine what must be done to resolve a page fault to this
        /// page.
        present: bool,
        // TODO shared unmapped page metadata. can wait until theres actually disk io.
        _0: u10 = 0,
        /// true if the PTE is in transition. this bit matches the sw_dirty bit on a present
        /// PTE, and in a transition PTE the rest of the PTE MUST MATCH EXACTLY the former
        /// present PTE. this is fine, as the sw_dirty bit is only used to determine whether
        /// a present page goes onto the standby or writeback lists when it is unmapped,
        /// and if a page is already in transition that state is stored in the PFM's status
        /// enum. the PFM may either be in the standby or writeback lists or performing paging
        /// io. if performing paging io, the page fault handler (which runs at IRQL 0 with
        /// interrupts enabled) will wait on the event that the PFM contains a pointer to.
        /// if in the standby or writeback lists, the page fault handler can remove the PFM
        /// from the relevant list, set transition to the target sw_dirty status depending on
        /// which list the PFM was removed from, and set the PTE present bit to resolve the
        /// page fault without IO or blocking
        transition: bool,
        /// if transition is false, committed is true if the page is either swapped out or
        /// pending allocation, and a page fault to this page should either allocate a zero
        /// page or initiate readback io.
        committed: bool,
        _1: u51 = 0,
    },
    valid: PresentPte,
    page_file: SwapFilePte,
    list: packed struct(u64) {
        present: bool = false,
        singleton: bool,
        _: u30 = 0,
        next: u32,
    },
    uint: u64,
    sint: i64,
    unset: packed struct(u64) {
        _: u64 = 0,
    },

    pub const zero: Pte = .{ .unset = .{} };
};

pub const SwapFilePte = packed struct(u64) {
    present: bool = false,
    _0: u10 = 0,
    transition: bool = false,
    committed: bool = true,
    _: u3 = 0,
    /// which swapfile the page is swapped to, from a global list.
    swapfile_index: u16,
    /// 0 means to always fill with a zero page. max value means memory-mapped view of a file,
    /// and the details of the mapping are stored in the process working set blocks in the block
    /// associated with this virtual address. because handles or file-object pointers are pointer
    /// sized, we cant fit them into the PTE with the rest of the PTE metadata we need. fortunately,
    /// the page fault handler has access to the virtual address directly in CR2 without having to
    /// somehow back-compute from the PTE (and in fact has to do the forward calculation to access
    /// the PTE), and can thus get the metadata block from the virtual address metadata tree.
    ///
    /// if the PTE requests a zero page, the page fault handler will search first for a free zero
    /// page, fall back to a free indeterminate page which it manually zeroes, and fall back to a
    /// standby page which must also be manually zeroed. if taking a standby page, the page's PTE
    /// should be transitioned to the swapfile-pending state. if no standby page is available, a
    /// condition variable is signalled by the writeback thread whenever it completes writeback
    /// for a page.
    /// if the PTE requests a specific swapped or memory-mapped-file-view page, then the physical
    /// page allocation should prioritize indetermine content free pages over zero pages but is
    /// otherwise the same, after which it should move both this PTE to the transition state,
    /// move the PFM to readback state, and initiate readback io.
    swapfile_page_index: u32,
};

pub const PresentPte = packed struct(u64) {
    present: bool = true,
    writable: bool,
    user_mode: bool,
    write_through: bool,
    cache_disable: bool,
    hw_accessed: bool = false,
    hw_dirty: bool = false,
    pat_size: bool,
    global: bool,
    copy_on_write: bool,
    sw_dirty: bool = false,
    _0: u1 = 0,
    addr: packed union {
        pfi: pfmdb.Pfi,
        large_page_flags: packed struct(pfmdb.Pfi) {
            pat: bool,
            _: std.meta.Int(.unsigned, @bitSizeOf(pfmdb.Pfi) - 1) = 0,
        },
    },
    _pad: PtePfiPad = 0,
    pk: u4,
    xd: bool,
};

pub const PageTable = *[std.mem.page_size / @sizeOf(Pte)]Pte;
