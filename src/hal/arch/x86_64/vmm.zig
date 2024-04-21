const pmm = @import("pmm.zig");
const paging = @import("paging.zig");
const entries = paging.entries;
const std = @import("std");

const apic = @import("../../apic.zig");
const memory = @import("../../memory.zig");

// the base where we plan to id-map physical memory
const idmap_base_4lvl: isize = -1 << 45;
const idmap_base_5lvl: isize = -1 << 53;

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
    try paging.map_range(0, idmap_base, pmm.max_phys_mem);
    try paging.map_range(0, -1 << 31, 1 << 31);
    paging.finalize_and_fix_root();
    pmm.enlarge_mapped_physical(memmap, idmap_base);
    apic.lapic_ptr = @ptrFromInt(@intFromPtr(apic.lapic_ptr) + @as(usize, @bitCast(idmap_base)));
}
