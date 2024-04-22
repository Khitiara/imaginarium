const pmm = @import("pmm.zig");
const paging = @import("paging.zig");
const entries = paging.entries;
const std = @import("std");

const apic = @import("../../apic.zig");
const memory = @import("../../memory.zig");

// the base where we plan to id-map physical memory
const idmap_base_4lvl: isize = -1 << 45;
const idmap_base_5lvl: isize = -1 << 53;

const log = std.log.scoped(.vmm);

pub fn init(memmap: []memory.MemoryMapEntry) !void {
    // when this method is called we assume the following:
    // 1. the pmm is already initialized with the bottom 2G of the bios memory map
    // 2. cr3 points to the paging table set up by the bootloader
    // 3. interrupts are *disabled*
    // therefore we have the following actions to take:
    // 1. duplicate the bootloader page table a new one of our own
    // 2. map with the largest possible pages the bulk of physical memory at base linear address idmap_base
    //      2.a. this means we need to map the uppermost largest block of the final memory map due to the LIFO nature
    //          of the pmm implementation - TODO: investigate ways to make this part lazier
    //      2.b. it may be easier to just up and map the entirety of physical memory immediately
    // 3. set cr3
    // 4. change the pmm's sequential mapping base address to idmap_base
    // 5. mark-free the rest of physical memory now that we know we can use it all
    // when this function returns, a page-fault exception will have correct behavior

    // our bootloader, bootelf, maps the following regions in its page table (linear -> phys)
    // a: 0..2G -> 0..2G
    // b: -2G..-0 -> 0..2G
    // whereas we will map:
    // a: 0..1M -> 0..1M
    // b: -2G..-0 -> 0..2G
    // c: (-1 << 45)... -> 0...max_phys_mem
    // note that the elf file from which this stage1 kernel was loaded is present in memory at physical
    // address 0x7E00. this should not be confused with the kernel binary image which is mapped per that elf
    // file by bootelf.

    const idmap_base = if (paging.features.five_level_paging) idmap_base_5lvl else idmap_base_4lvl;
    paging.using_5_level_paging = paging.features.five_level_paging;
    log.info("mapping all phys mem at 0x{X}", .{idmap_base});
    try paging.map_range(0, idmap_base, pmm.max_phys_mem);
    log.info("mapping bottom 2G at 0x{X}", .{@as(usize, @bitCast(@as(isize, -1 << 31)))});
    try paging.map_range(0, -1 << 31, 1 << 31);
    log.info("mapping bottom 4M at 0", .{});
    try paging.map_range(0, 0, 1 << 22);
    // dump_paging_debug();
    log.info("finished page tables, applying", .{});
    paging.load_pgtbl();
    log.info("pages mapped, relocating and enlarging pmm", .{});
    pmm.enlarge_mapped_physical(memmap, idmap_base);
    log.info("high physical memory given to pmm", .{});
    paging.finalize_and_fix_root();
    apic.lapic_ptr = @ptrFromInt(@intFromPtr(apic.lapic_ptr) + @as(usize, @bitCast(idmap_base)));
}

// noinline fn dump_paging_debug() void {
//     const addr = @returnAddress();
//     const split: paging.SplitPagingAddr = @bitCast(addr);
//     log.info("address to map: 0x{X:0>16} {b:0>9}:{b:0>9}:{b:0>9}:{b:0>9}:{b:0>9}:{b:0>12}", .{ addr, @as(u9, @bitCast(split.pml4)), split.dirptr, split.directory, split.table, split.page, split.byte });
//     const dirptr = paging.pgtbl.?[split.dirptr].get_phys_addr();
//     log.info("dirptr at 0x{X}", .{dirptr});
//     const directory = pmm.ptr_from_physaddr(paging.Table(paging.entries.PDPTE), dirptr)[split.directory].get_phys_addr();
//     log.info("directory at 0x{X}", .{directory});
//     const direntry = pmm.ptr_from_physaddr(paging.Table(paging.entries.PDE), directory)[split.table];
//     if (direntry.page_size) {
//         log.info("2mb page at 0x{X}", .{direntry.get_phys_addr()});
//     } else {
//         const table = direntry.get_phys_addr();
//         log.info("table at 0x{X}", .{table});
//         log.info("4k page at 0x{X}", .{pmm.ptr_from_physaddr(paging.Table(paging.entries.PTE), table)[split.page].get_phys_addr()});
//     }
// }
