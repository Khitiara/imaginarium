//! the kernel memory manager

const std = @import("std");
const pte = @import("pte.zig");
const pfmdb = @import("pfmdb.zig");
const cmn = @import("cmn");
const PhysAddr = cmn.types.PhysAddr;

const log = std.log.scoped(.mm);
const pmm_log = std.log.scoped(.@"mm.phys");
const vmm_log = std.log.scoped(.@"mm.virt");

pub fn init_mm(memmap: []cmn.memmap.Entry) !void {
    const hhdm_base: usize = @intFromPtr(@extern(*u64, .{ .name = "__base__" }));
    const kernel_size = std.mem.alignForwardLog2(@intFromPtr(@extern(*u64, .{ .name = "__kernel_phys_end__" })), 24);

    // find the earliest free usable page. at this point, bootelf guarantees that only physical memory
    // from physical address 0 through __kernel_end__ - __base__ (exposed by the linker script as
    // __kernel_phys_end__) is in use for allocated memory. therefore, iterating the E820 memory map
    // to find the first usable physical address not before __kernel_phys_end__ is sufficient to find the next
    // free memory. we require at least two 2M large pages worth of free space available to start recording
    // the PFMDB (as the endpoint isnt guaranteed on a large page boundary).
    const next_free_page_addr: usize = for (memmap) |entry| {
        if (entry.type == .normal) {
            var base = @intFromEnum(entry.base);
            var size = entry.size;
            const end = base + size;
            if (end < kernel_size) {
                log.debug("skipping 0x{X}..0x{X} as it is wholly within space already containing the kernel", .{ base, end });
                continue;
            }
            if (base < kernel_size) {
                const diff = kernel_size - base;
                log.debug("adjusting 0x{X}..0x{X} forward 0x{X} bytes to avoid initial kernel block", .{ base, end, diff });
                base = kernel_size;
                size -= diff;
            }
            if (size >= 2 << pfmdb.LargePageOffsetBits) {
                break @enumFromInt(std.mem.alignForwardLog2(base, pfmdb.PageOffsetBits));
            }
        }
    } else {
        return error.OutOfMemory;
    };
    // align forward to a large page so we can fit the first 2M page of the PFMDB. hopefully we only need the one
    // for now, which will fit at least 65K PFM entries, to describe enough further free pages to allocate starting
    // page tables.
    const pfmdb_phys_addr = std.mem.alignForwardLog2(next_free_page_addr, pfmdb.LargePageOffsetBits);

    // safety check, adding more 2M pages as needed to ensure the initial PFM is recording its own pages.
    // once we have intial page tables, the page fault handler will be able to find enough free pages to
    // allocate more PFMDB and any required page structures.
    //
    // because the bootloader gives us an HHDM, the initial PFMDB MUST be entirely contiguous in physical
    // memory, which is an annoying constraint on us
    var pfmdb_len: usize = 1 << pfmdb.LargePageOffsetBits;
    while ((((pfmdb_phys_addr + pfmdb_len) << pfmdb.PageOffsetBits) * @sizeOf(pte.Pfm)) >= pfmdb_len) {
        pfmdb_len += 1 << pfmdb.LargePageOffsetBits;
        log.warn("reserving extra large page for bootstrap PFMDB", .{});
    }

    // and slice it
    const initial_pfmdb: []pfmdb.Pfm = std.mem.bytesAsSlice(pfmdb.Pfm, @as([*]u8, @ptrFromInt(pfmdb_phys_addr + hhdm_base))[0..std.mem.alignBackward(pfmdb.Pfm, pfmdb_len)]);

    log.info(
        \\initial PFMDB allocation: {d} large pages for {x} bytes
        \\NOTE: stores {x} pages of metadata
    , .{
        pfmdb_len >> pfmdb.LargePageOffsetBits,
        pfmdb_len,
        initial_pfmdb.len,
    });

    // and create the bootstrap PFMDB. the bootstrapping will load normal-use pages into the free list
    // so we can use the free list for page table allocation instead of re-iterating the memory map
    _ = pfmdb.bootstrap_pfmdb(initial_pfmdb, memmap);
    pmm_log.debug("bootstrap PFMDB created",.{});

    const pfmdb_initial_alloc_phys_end = pfmdb_phys_addr + pfmdb_len;

    // the PFMDB bootstrap marks all usable pages as free, which means that the PFMDB itself and the
    // kernel executable are currently in the free list, so fix that. the bootstrap-mark-allocated function
    // leaves the PFMs in an invalid state, as the back-link to the PTE is invalid.

    // un-free the PFMDB
    pfmdb.bootstrap_mark_allocated(initial_pfmdb, pfmdb_phys_addr >> pfmdb.PageOffsetBits, pfmdb_initial_alloc_phys_end >> pfmdb.PageOffsetBits);
    // un-free the kernel
    pfmdb.bootstrap_mark_allocated(initial_pfmdb, 0, kernel_size >> pfmdb.PageOffsetBits);
}

// fn alloc_page_table(hhdm_base: usize, initial_pfmdb: []pfmdb.Pfm, pfmdb_phys_start: usize, pfmdb_initial_alloc_phys_end: usize, next_page_phys_addr: *usize) *[512]pte.Pte {}

comptime {
    _ = init_mm;
}
