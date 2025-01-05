//! bootstrapping for the kernel memory manager
//!
//! when MM bootstrapping is complete, the following systems will be usable:
//! - PFM database
//! - global system page tables
//! - nonpaged pool
//! - MMIO mapping
//!
//! for this to work, the bootloader must provide:
//! - a physical memory map with free locations properly marked
//! - a higher-half direct map which must map at least all general
//!     purpose usable physical memory
//!
//! the bootstrapping process works in stages:
//! 1. new page tables are allocated from the bootloader-provided HHDM, consisting of
//!     mappings of the kernel and a recursive page table mapping with index 0x1F7/0o767.
//!     physical pages are allocated from the largest memory map region of usable free
//!     memory in the map provided by the bootloader.
//! 2. new page tables are loaded and the page frame metadata database and its presence
//!     bitmap are mapped using the recursive page tables, allocating page table storage
//!     from the large free descriptor as in stage 1. all descriptors except the large
//!     free descriptor are added to the pfm database in a bare state.
//! 3. the remaining free pages of the large free descriptor are added to the pfm database,
//!     and allocation is temporarily not possible. the pfm database entries for mapped
//!     pages are filled out with back-pointers to their page table entries and any mapped
//!     pages incorrectly in the free list are removed from the free list as safety for
//!     bootloader memory maps that neglect to mark the mapping of the loaded kernel itself.
//! 4. the pfm database is fully usable, and allocation of physical pages is now possible
//!     from the pfm database free list. during this stage, framebuffers etc are mapped and
//!     data structures relevant to the implementation of nonpaged allocator pools are
//!     created and initialized as needed
//! after stage 4 completes, processor control blocks etc can be allocated and a general-
//! purpose allocator initialized on top of the nonpaged pool. all functions of the memory
//! manager are then accessible except for paged pool, which relies on filesystem init to
//! manage swapfiles.

const std = @import("std");
const pte = @import("pte.zig");
const pfmdb = @import("pfmdb.zig");
const cmn = @import("cmn");
const boot = @import("../../boot/boot_info.zig");
const map = @import("map.zig");
const arch = @import("../arch/arch.zig");

const PhysAddr = cmn.types.PhysAddr;
const Pfi = pfmdb.Pfi;
const Pte = pte.Pte;
const MemoryDescriptor = boot.memory_map.MemoryDescriptor;

const log = std.log.scoped(.@"mm.init");

const EarlyMemoryProbe = struct {
    large_free_descriptor: *MemoryDescriptor,
    lowest_phys_page: Pfi,
    highest_phys_page: Pfi,
    phys_page_count: usize,
    free_page_count: usize,
};

var bootstrap_stage: u4 = 0;

/// does an initial probe of the memory map from the bootloader.
/// in doing so, we identify the descriptor describing the largest block of free memory
/// from which the PFMDB and first PTEs will be allocated. in addition the maximum
/// and minimum page indices are determined - the maximum will be used for determining the
/// page count of the PFMDB and the rest are currently for informational purposes only
fn early_probe_memory_map(mm: []MemoryDescriptor) linksection(".init") EarlyMemoryProbe {
    var biggest_free_pages: usize = 0;
    var phys_page_count: usize = 0;
    var free_page_count: usize = 0;
    var lowest_phys_page: Pfi = std.math.maxInt(Pfi);
    var highest_phys_page: Pfi = 0;
    var e: *MemoryDescriptor = undefined;
    for (mm, 0..) |*entry, i| {
        log.debug("[STAGE {d}]: Memory Descriptor {d}: Type {s} Base {x} Pages {x}", .{ bootstrap_stage, i, @tagName(entry.memory_kind), entry.base_page, entry.page_count });
        if (entry.memory_kind != .bad_memory) {
            phys_page_count += entry.page_count;
        }
        // if (i == mm.len - 1 and entry.memory_kind == .reserved) {
        //     break;
        // }
        if (entry.base_page < lowest_phys_page) {
            lowest_phys_page = entry.base_page;
        }
        const index = entry.base_page + entry.page_count;
        if (index > highest_phys_page) {
            highest_phys_page = index - 1;
        }
        sw: switch (entry.memory_kind) {
            .usable => {
                if (entry.page_count > biggest_free_pages) {
                    e = entry;
                    biggest_free_pages = entry.page_count;
                }
                continue :sw .bootloader_reclaimable;
            },
            .bootloader_reclaimable => {
                free_page_count += entry.page_count;
            },
            else => {},
        }
    }

    return .{
        .large_free_descriptor = e,
        .lowest_phys_page = lowest_phys_page,
        .highest_phys_page = highest_phys_page,
        .phys_page_count = phys_page_count,
        .free_page_count = free_page_count,
    };
}

fn bootstrap_alloc_page() linksection(".init") Pfi {
    if (tmp_desc.page_count == 0) @panic("OOM in bootstrap!");
    const pfi = tmp_desc.base_page;
    tmp_desc.base_page += 1;
    tmp_desc.page_count -= 1;
    return pfi;
}

var valid_pte: Pte linksection(".init") = .{
    .valid = .{
        .writable = true,
        .user_mode = false,
        .write_through = false,
        .cache_disable = true,
        .pat_size = false,
        .global = false,
        .copy_on_write = false,
        .sw_dirty = false,
        .addr = .{ .pfi = 0 },
        .pk = 0,
        .xd = false,
    },
};

const PfiBreakdown = packed union {
    pfi: Pfi,
    breakdown: packed struct(Pfi) {
        pte: u9,
        pde: u9,
        ppe: u9,
        pxe: u9,
    },
};

inline fn pxe_index_from_addr(addr: usize, level: usize) linksection(".init") u9 {
    return @truncate((addr >> (9 * (level - 1) + 12)));
}

const Page = *align(4096) [4096]u8;
const HhdmType = [*]align(4096) [4096]u8;

fn map_block(block: pte.PageTable) linksection(".init") void {
    for (block) |*e| {
        valid_pte.valid.addr.pfi = bootstrap_alloc_page();
        e.* = valid_pte;
        @memset(bootstrap_access_pte(e.*, hhdm), 0);
    }
}

inline fn create_or_access_pxe(entry: *Pte) linksection(".init") pte.PageTable {
    if (!entry.unknown.present) {
        valid_pte.valid.addr.pfi = bootstrap_alloc_page();
        entry.* = valid_pte;
        @memset(bootstrap_access_pte(entry.*), 0);
    }
    return @ptrCast(bootstrap_access_pte(entry.*));
}

/// add a direct mapping of a region of physical addresses to virtual addresses in the page tables.
/// this function assumes that the recursive page mappings dont yet exist and relies on the HHDM
/// to access page tables. it is thus somewhat inefficient compared to what can be done after the
/// mm bootstrapping is complete and should be used as little as possible.
fn bootstrap_direct_map_region(start_virt: Pfi, start_phys: Pfi, end_phys: Pfi, lvl4_tbl: pte.PageTable) linksection(".init") void {
    var virt: PfiBreakdown = .{ .pfi = start_virt };
    var phys: Pfi = start_phys;
    while (phys <= end_phys) : ({
        phys += 1;
        virt.pfi += 1;
    }) {
        const pp = create_or_access_pxe(&lvl4_tbl[virt.breakdown.pxe]);
        const pd = create_or_access_pxe(&pp[virt.breakdown.ppe]);
        // if we can large page then large page
        // if (std.mem.isAligned(virt.pfi, 512) and std.mem.isAligned(phys, 512) and end_phys - phys >= 512) {
        //     valid_pte.valid.addr.pfi = phys;
        //     valid_pte.valid.pat_size = true;
        //     pd[virt.breakdown.pde] = valid_pte;
        //     valid_pte.valid.pat_size = false;
        //     phys += 511;
        //     virt.pfi += 511;
        //     continue;
        // }
        // log.debug("mapped page {x} to {x}", .{phys, virt.pfi});
        const pt = create_or_access_pxe(&pd[virt.breakdown.pde]);
        valid_pte.valid.global = true;
        valid_pte.valid.addr.pfi = phys;
        pt[virt.breakdown.pte] = valid_pte;
        valid_pte.valid.global = false;
    }
}

fn bootstrap_access_pte(e: Pte) linksection(".init") Page {
    return &hhdm[e.valid.addr.pfi];
}

var hhdm: HhdmType linksection(".init") = undefined;
var tmp_desc: *MemoryDescriptor linksection(".init") = undefined;
var backup_desc: MemoryDescriptor linksection(".init") = undefined;
var probe: EarlyMemoryProbe linksection(".init") = undefined;

/// performs initial page table setup.
/// when this function returns, THE NEW PAGE TABLE IS LOADED. BE CAREFUL.
fn init_mm_early() linksection(".init") !void {
    // get memory map from the bootloader protocol
    const memmap = boot.memmap;
    // and probe it
    probe = early_probe_memory_map(memmap);

    log.info(
        \\[STAGE {[stage]d}]: early memory map probe complete
        \\    physical pages detected with indices {[min]x:0>[pfiwidth]}..{[max]x:0>[pfiwidth]}
        \\    for a total of {[total]x:0>[pfiwidth]} total and {[free]x:0>[pfiwidth]} free pages
    , .{
        .stage = bootstrap_stage,
        .min = probe.lowest_phys_page,
        .max = probe.highest_phys_page,
        .total = probe.phys_page_count,
        .free = probe.free_page_count,
        .pfiwidth = @bitSizeOf(Pfi) / 4,
    });

    log.info(
        "[STAGE {d}]: bootstrapping will use the block at base PFI {x} with length {x} pages",
        .{ bootstrap_stage, probe.large_free_descriptor.base_page, probe.large_free_descriptor.page_count },
    );

    // make a temporary copy of the large free descriptor.
    // we'll use the original descriptor in the map to track
    // pages allocated during bootstrap which means we need
    // to keep the original around for later.
    tmp_desc = probe.large_free_descriptor;
    backup_desc = probe.large_free_descriptor.*;

    // bootloader gives a [*]u8. cast to [*][4096]u8 so we can index by PFI. aligncast is for general safety
    // and is guaranteed safe because of the definition of the HHDM.
    hhdm = @alignCast(@ptrCast(boot.hhdm_base()));

    log.info("[STAGE {d}]: bootstrapping will use HHDM with base {x} to access memory during stage 1", .{ bootstrap_stage, @intFromPtr(hhdm) });

    // * INITIAL PAGE TABLES *

    // setup our lvl4 table
    const lvl4_table_pfi = bootstrap_alloc_page();
    log.debug("new lvl4 table at pfi {x}", .{lvl4_table_pfi});
    const lvl4_tbl: pte.PageTable = @ptrCast(&hhdm[lvl4_table_pfi]);

    // recursive page tables.
    // took me a hot minute to understand how this actually works and its
    // kind messed up tbh but very effective.
    //
    // tldr to get the nth page table for a virtual address, shift the address
    // right by 3 + (9 * n) bits, and then stack on (4 - n) 0o767s on front and
    // sign extend.
    //
    // e.g. the 48-bit octal address 123_456_712_345_6712 has page tables at octal addresses:
    // - PTE: 767_123_456_712_3450,
    // - PDE: 767_767_123_456_7120,
    // - PPE: 767_767_767_123_4560,
    // - PXE: 767_767_767_767_1230.
    //
    // and the root page table has octal address 767_767_767_767_7670.
    //
    // octal 767/hex 1F7 was chosen to place the page table root at 0xFFFF_FB80_0000_0000.
    valid_pte.valid.addr.pfi = lvl4_table_pfi;
    lvl4_tbl[map.pte_recurse_index] = valid_pte;

    // give each of the other 127 kernel mode PXE entries a blank page, leaving usermode PXE entries blank.
    for (lvl4_tbl[0x100..], 0x100..) |*e, i| {
        if (i != map.pte_recurse_index) {
            valid_pte.valid.addr.pfi = bootstrap_alloc_page();
            e.* = valid_pte;
            @memset(bootstrap_access_pte(e.*), 0);

            // log.debug("created table to be at {x} for pxe at {x} index {x}", .{map.ppe_base_addr + 4096 * i, map.pxe_base_addr + 8 * i, i});
        }
    }

    log.info("[STAGE {d}]: top level table created and all PXEs allocated", .{bootstrap_stage});

    // * ADD KERNEL MAPPINGS *

    const krnl_location = boot.get_kernel_image_info();
    const krnl_ptes = krnl_location.kernel_len_pages;
    const krnl_pdes = std.math.divCeil(usize, krnl_ptes, 512) catch unreachable;
    const krnl_ppes = std.math.divCeil(usize, krnl_pdes, 512) catch unreachable;

    const krnl_pxe_idx = pxe_index_from_addr(krnl_location.kernel_virt_addr_base, 4);
    const krnl_ppe_idx_base = pxe_index_from_addr(krnl_location.kernel_virt_addr_base, 3);
    const krnl_pde_idx_base = pxe_index_from_addr(krnl_location.kernel_virt_addr_base, 2);
    const krnl_pte_idx_base = pxe_index_from_addr(krnl_location.kernel_virt_addr_base, 1);

    log.debug(
        \\[STAGE {d}]: kernel mapping is {x} pages ({x} pdes, {x} ppes) at base 177777_{o:0>3}_{o:0>3}_{o:0>3}_{o:0>3}_0000 (that's {x})
        \\    physical kernel base is {x}
    , .{
        bootstrap_stage,                                                            krnl_ptes,
        krnl_pdes,                                                                  krnl_ppes,
        krnl_pxe_idx,                                                               krnl_ppe_idx_base,
        krnl_pde_idx_base,                                                          krnl_pte_idx_base,
        krnl_location.kernel_virt_addr_base & (~@as(usize, std.mem.page_size - 1)), krnl_location.kernel_phys_addr_base,
    });

    const krnl_base_ppfi: Pfi = @intCast(krnl_location.kernel_phys_addr_base >> 12);
    const krnl_end_ppfi: Pfi = @intCast(krnl_base_ppfi + krnl_location.kernel_len_pages);
    bootstrap_direct_map_region(@truncate(krnl_location.kernel_virt_addr_base >> 12), krnl_base_ppfi, krnl_end_ppfi, lvl4_tbl);

    log.info("[STAGE {d}]: kernel mappings created", .{bootstrap_stage});



    // try dump_page_tables(lvl4_table_pfi);

    var cr3 = arch.control_registers.read(.cr3);
    // log.debug("OLD CR3: {x}", .{@as(usize, @bitCast(cr3))});

    // try dump_page_tables(@intCast(cr3.pml45_base_addr));
    cr3.pml45_base_addr = lvl4_table_pfi;
    // log.debug("NEW CR3: {x}", .{@as(usize, @bitCast(cr3))});

    arch.control_registers.write(.cr3, .{
        .pcid = .{
            .nopcid = .{
                .pwt = false,
                .pcd = true,
            },
        },
        .pml45_base_addr = lvl4_table_pfi,
        .permit_keep_tlb_pcide = false,
    });

    log.info("[STAGE {d}]: wrote CR3; stage 1 finished", .{bootstrap_stage});

    var cr4 = arch.control_registers.read(.cr4);
    cr4.pcide = false;
    cr4.pge = true;
    arch.control_registers.write(.cr4, cr4);

    log.info("[STAGE {d}]: wrote CR4 to disable PCIDE", .{bootstrap_stage});
}

inline fn startend_to_slice(comptime T: type, start: *T, end: *T) linksection(".init") []T {
    const len = @intFromPtr(end) - @intFromPtr(start);
    const cnt = len / @sizeOf(T) + 1;
    return @as([*]T, @ptrCast(start))[0..cnt];
}

inline fn make_tbl_mapper(comptime from_addr: fn (usize) *Pte) fn (usize, usize) void {
    return struct {
        pub fn late_bootstrap_map_table(base: usize, end: usize) linksection(".init") void {
            for (startend_to_slice(Pte, from_addr(base), from_addr(end))) |*e| {
                if (!e.unknown.present) {
                    const new_tbl = bootstrap_alloc_page();
                    valid_pte.valid.addr.pfi = new_tbl;
                    e.* = valid_pte;
                    @memset(map.addr_from_pte(e), 0);
                }
            }
        }
    }.late_bootstrap_map_table;
}

const late_bootstrap_map_ppes = make_tbl_mapper(map.ppe_from_addr);
const late_bootstrap_map_pdes = make_tbl_mapper(map.pde_from_addr);
const late_bootstrap_map_ptes = make_tbl_mapper(map.pte_from_addr);

fn late_bootstrap_alloc_block(base_virt: usize, size: usize) linksection(".init") []u8 {
    const end = base_virt + size;
    late_bootstrap_map_ppes(base_virt, end);
    late_bootstrap_map_pdes(base_virt, end);
    valid_pte.valid.global = true;
    late_bootstrap_map_ptes(base_virt, end);
    valid_pte.valid.global = false;

    return @as([*]u8, @ptrFromInt(base_virt))[0..size];
}

var bootstrap_reclaimable_list: pfmdb.PfmList = .{ .associated_status = .invalid };

fn bootstrap_add_descriptor_to_pfmdb(desc: *const MemoryDescriptor) linksection(".init") void {
    switch (desc.memory_kind) {
        .usable => {
            // free memory.
            var idx = desc.base_page + desc.page_count;
            log.debug("[STAGE {d}]: marking as free descriptor with type {s} from {x}..{x}", .{ bootstrap_stage, @tagName(desc.memory_kind), desc.base_page, idx });
            while (idx > desc.base_page) {
                idx -= 1;
                pfmdb.free_list.push(idx);
            }
        },
        .bootloader_reclaimable => {
            // bootloader-reclaimable memory.
            // memory here is normal usable ram but is currently in-use and NOT mapped by our new page tables.
            // therefore it can only be freed once we are done with the bootloader protocol features.
            //
            // e.g. somewhere in here is limine's ap bootstrapping stack and page tables so
            // we cant free this now unless we want to do ap bootstrapping ourself
            var idx = desc.base_page + desc.page_count;
            log.debug("[STAGE {d}]: marking as temporarily invalid descriptor with type {s} from {x}..{x}", .{ bootstrap_stage, @tagName(desc.memory_kind), desc.base_page, idx });
            while (idx > desc.base_page) {
                idx -= 1;
                bootstrap_reclaimable_list.push(idx);
            }
        },
        .bootstrap_in_use, .loaded_image => {
            var idx = desc.base_page + desc.page_count;
            log.debug("[STAGE {d}]: marking as mapped descriptor with type {s} from {x}..{x}", .{ bootstrap_stage, @tagName(desc.memory_kind), desc.base_page, idx });
            while (idx > desc.base_page) {
                idx -= 1;
                pfmdb.pfm_db[idx]._1.status = .mapped;
            }
        },
        else => return, // neither active nor free so we leave it blank as if IO.
    }
    pfmdb.pfm_bitmap.setRangeValue(.{ .start = desc.base_page, .end = desc.base_page + desc.page_count }, true);
}

fn bootstrap_add_ptes_to_pfmdb() linksection(".init") void {}

/// does the initial fill of the PFMdb. from the memory map
fn bootstrap_fill_pfmdb() linksection(".init") void {
    // loop through the memory map
    for (boot.memmap) |*d| {
        switch (d.memory_kind) {
            .usable, .bootloader_reclaimable, .bootstrap_in_use, .loaded_image => {},
            else => {
                // skip anything that isnt memory we can use (either MMIO or acpi/firmware storage etc)
                log.debug("[STAGE {d}]: skipping for pfmdb descriptor with type {s} from {x}..{x}", .{
                    bootstrap_stage,
                    @tagName(d.memory_kind),
                    d.base_page,
                    d.base_page + d.page_count,
                });
                continue;
            },
        }
        // allocate and map the section of the PFMdb that we need for this block
        // if its the free descriptor we've been allocating from then we still need to map it,
        // including the PFMs for pages we've already allocated. therefore we use the backup descriptor
        // for page mapping
        const desc = if (d == tmp_desc) &backup_desc else d;
        valid_pte.valid.global = true;
        late_bootstrap_map_ptes(@intFromPtr(pfmdb.pfm_db + desc.base_page), @intFromPtr(pfmdb.pfm_db + desc.base_page + desc.page_count));
        valid_pte.valid.global = false;

        // if it isnt the backup descriptor then d wasnt the free descriptor and we can add the pages to the PFMdb.
        // anything marked as loaded image by the bootloader gets included here and marked as active.
        // if the kernel image isnt marked in the memory map then the secondary fill from the page tables ought
        // to detect that and remove relevant pages from the free list but if its in the memory map we might as
        // well skip that extra work later
        if (desc != &backup_desc) {
            bootstrap_add_descriptor_to_pfmdb(desc);
        }
    }

    bootstrap_stage = 3;

    // we are done using the tmp descriptor to allocate pages, so we can add remaining free pages to the pfmdb.
    // this also adds them to the free list so we can use the pfmdb to allocate pages going forward anyway.
    // this effectively marks the end of stage 2 of the mm bootstrapping
    bootstrap_add_descriptor_to_pfmdb(tmp_desc);

    // we need to add to the pfmdb the pages we allocated from the bootstrap descriptor too
    var inuse_desc = backup_desc;
    inuse_desc.memory_kind = .bootstrap_in_use;
    inuse_desc.page_count = tmp_desc.base_page - backup_desc.base_page;
    bootstrap_add_descriptor_to_pfmdb(&inuse_desc);
    tmp_desc.* = backup_desc;

    log.info("[STAGE {d}]: PFM db initialized without PTE info", .{bootstrap_stage});
}

// puts free pages into the PFMDB but only allocating for free blocks and for the bitmap
fn bootstrap_init_pfmdb() linksection(".init") void {

    // the number of pages we need for the PFM db
    const pfm_allocation = b: {
        const a = (probe.highest_phys_page + 1) * @sizeOf(pfmdb.Pfm);
        // if we add more caching etc to the pfmdb region we can add that in here
        // before dividing out to get page count.
        break :b std.math.divCeil(usize, a, std.mem.page_size) catch unreachable;
    };

    log.info("[STAGE {d}]: PFM db will need {x} pages ({x} page tables, {x} page directories, {x} page directory lists)", .{
        bootstrap_stage,
        pfm_allocation,
        std.math.divCeil(usize, pfm_allocation, 512) catch unreachable,
        std.math.divCeil(usize, pfm_allocation, 512 * 512) catch unreachable,
        std.math.divCeil(usize, pfm_allocation, 512 * 512 * 512) catch unreachable,
    });

    const bitmap_bytes = std.math.divCeil(usize, probe.highest_phys_page, 8) catch unreachable;
    const bitmap_masks = std.mem.alignForward(usize, bitmap_bytes, 8);

    late_bootstrap_map_ppes(map.pfm_db_addr, map.pfm_db_addr + (pfm_allocation << 12));
    log.debug("[STAGE {d}]: PFM ppes mapped", .{bootstrap_stage});
    late_bootstrap_map_pdes(map.pfm_db_addr, map.pfm_db_addr + (pfm_allocation << 12));
    log.debug("[STAGE {d}]: PFM pdes mapped", .{bootstrap_stage});

    _ = late_bootstrap_alloc_block(map.pfm_map_tracking_addr, bitmap_masks);
    pfmdb.pfm_bitmap.bit_length = probe.highest_phys_page + 1;
    log.debug("[STAGE {d}]: PFM bitmap ptes mapped", .{bootstrap_stage});

    bootstrap_fill_pfmdb();
}

noinline fn init_mm_impl() linksection(".init") !void {
    bootstrap_stage = 1;
    // do early page table things
    try init_mm_early();

    bootstrap_stage = 2;
    // ok now the new page tables are loaded.
    // therefore, we MUST NOT use hhdm after this point.
    // bootloader reclaimable memory is also unmapped now,
    // but everything we care about from there is copied into
    // variables in kernel space.

    bootstrap_init_pfmdb();
}

/// initialize the memory manager.
/// once this function returns, new page tables will be in place, with the kernel and PFMDB
/// mapped and a recursive page table map in place. in addition, the non-paged and mmio-address pools will be
/// in a minimal working state for further allocations, and bootloader structures in reclaimable
/// memory will be copied to managed memory and bootloader-reclaimable memory will have been
/// reclaimed. in addition, the entire `.init` section will be reclaimed.
pub fn init_mm() !void {
    try init_mm_impl();
}

pub fn dump_page_tables(lvl4: Pfi) !void {
    const lvl4_tbl: pte.PageTable = @ptrCast(&hhdm[lvl4]);
    log.debug("DUMPING PAGE TABLES", .{});
    const writer = arch.SerialWriter.writer();
    try writer.print("CR3: {x}\n", .{lvl4});
    for (lvl4_tbl, 0..) |pxe, x| {
        if (pxe.unknown.present) {
            try writer.print("    [{o:0>3}]: ", .{x});
            try writer.print("{x}\n", .{pxe.valid.addr.pfi});
            if (x == 0x1F7) {
                try writer.print("        RECURSIVE\n", .{});
            } else {
                for (@as(pte.PageTable, @ptrCast(bootstrap_access_pte(pxe))), 0..) |ppe, p| {
                    if (ppe.unknown.present) {
                        try writer.print("        [{o:0>3}]: ", .{p});
                        try writer.print("{x}\n", .{ppe.valid.addr.pfi});
                        for (@as(pte.PageTable, @ptrCast(bootstrap_access_pte(ppe))), 0..) |pde, d| {
                            if (pde.unknown.present) {
                                try writer.print("            [{o:0>3}]: ", .{d});
                                try writer.print("{x}\n", .{pde.valid.addr.pfi});
                                for (@as(pte.PageTable, @ptrCast(bootstrap_access_pte(pde))), 0..) |pg, t| {
                                    if (pg.unknown.present) {
                                        try writer.print("                [{o:0>3}]: ", .{t});
                                        try writer.print("{x}\n", .{pg.valid.addr.pfi});
                                    } else {
                                        // try writer.writeAll("not present\n");
                                    }
                                }
                            } else {
                                // try writer.writeAll("not present\n");
                            }
                        }
                    }
                }
            }
        }
    }
}
