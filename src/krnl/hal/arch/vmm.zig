const pmm = @import("pmm.zig");
const paging = @import("paging.zig");
const entries = paging.entries;
const std = @import("std");
const ctrl_registers = @import("ctrl_registers.zig");
const mcfg = @import("../acpi/mcfg.zig");

const apic = @import("../apic/apic.zig");
const cmn = @import("cmn");

// the base where we plan to id-map physical memory
const idmap_base_4lvl: isize = -1 << 45;
const idmap_base_5lvl: isize = -1 << 53;

const log = std.log.scoped(.vmm);

const PhysAddr = pmm.PhysAddr;

var phys_mapping_range_bits: u6 = undefined;

pub fn init(memmap: []cmn.memmap.Entry) !void {
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

    paging.using_5_level_paging = paging.features.five_level_paging and ctrl_registers.read(.cr4).la57;
    const idmap_base = if (paging.using_5_level_paging) idmap_base_5lvl else idmap_base_4lvl;
    // this `and` should be redundant given cr4.12 should be 0 if la57 isnt supported but w/e
    log.info("mapping all phys mem at 0x{X}", .{@as(usize, @bitCast(idmap_base))});
    phys_mapping_range_bits = if (paging.using_5_level_paging) @min(paging.features.maxphyaddr, 48) else @min(paging.features.maxphyaddr, 39);
    log.debug("phys mapping range of {d} bits", .{phys_mapping_range_bits});
    try paging.map_range(.nul, idmap_base, @as(usize, 1) << phys_mapping_range_bits);
    log.info("mapping bottom {X} at 0x{X}", .{ pmm.kernel_size, @as(usize, @bitCast(@as(isize, -1 << 31))) });
    try paging.map_range(.nul, -1 << 31, pmm.kernel_size);
    // log.info("mapping bottom 4M at 0", .{});
    // try paging.map_range(0, 0, 1 << 22);
    // dump_paging_debug();
    log.info("finished page tables, applying", .{});
    // const m = pmm.ptr_from_physaddr([*]memory.MemoryMapEntry, @intFromPtr(memmap.ptr))[0..memmap.len];
    paging.load_pgtbl();
    log.info("pages mapped, relocating and enlarging pmm", .{});
    pmm.enlarge_mapped_physical(memmap, idmap_base);
    log.info("high physical memory given to pmm", .{});
    paging.finalize_and_fix_root();
}

pub fn phys_from_virt(virt: anytype) usize {
    // if the address is in the physically mapped block then just do the fast math
    if (virt > pmm.phys_mapping_base and @log2(virt - pmm.phys_mapping_base) <= phys_mapping_range_bits) {
        return pmm.physaddr_from_ptr(@as(*anyopaque, @ptrFromInt(virt)));
    }

    // otherwise actually trace the page structures
    std.debug.assert(@TypeOf(virt) == usize or @TypeOf(virt) == isize);
    const split: paging.SplitPagingAddr = @bitCast(virt);
    const dirptr = paging.pgtbl.?[split.dirptr].get_phys_addr();
    const directory = pmm.ptr_from_physaddr(paging.Table(paging.entries.PDPTE), dirptr)[split.directory];
    if (directory.page_size) {
        // gig page
        return directory.get_phys_addr() + @as(usize, @bitCast(virt)) & ((1 << 30) - 1);
    }
    const direntry = pmm.ptr_from_physaddr(paging.Table(paging.entries.PDE), directory.get_phys_addr())[split.table];
    if (direntry.page_size) {
        // 2mb page
        return direntry.get_phys_addr() + @as(usize, @bitCast(virt)) & ((1 << 21) - 1);
    }
    // regular-ass 4k page
    const page = pmm.ptr_from_physaddr(paging.Table(paging.entries.PTE), direntry.get_phys_addr())[split.page];
    return page.get_phys_addr() + split.byte;
}

pub const raw_page_allocator = struct {
    vtab: std.mem.Allocator.VTable = .{ .alloc = alloc, .resize = resize, .free = free },

    pub fn allocator(self: *const @This()) std.mem.Allocator {
        return .{
            .ptr = undefined,
            .vtable = &self.vtab,
        };
    }

    fn alloc(_: *anyopaque, len: usize, ptr_align: u8, _: usize) ?[*]u8 {
        const alloc_len = pmm.get_allocation_size(@max(@as(usize, 1) << @truncate(ptr_align), len));

        const ptr = pmm.ptr_from_physaddr([*]u8, pmm.alloc(alloc_len) catch |err| {
            switch (err) {
                error.OutOfMemory => return null,
                else => {
                    std.debug.panicExtra(@errorReturnTrace(), @returnAddress(), "PMM allocator: {}", .{err});
                },
            }
        });

        return ptr;
    }

    fn resize(_: *anyopaque, old_mem: []u8, old_align: u8, new_size: usize, ret_addr: usize) bool {
        const old_alloc = pmm.get_allocation_size(@max(old_mem.len, old_align));

        const paddr = pmm.physaddr_from_ptr(old_mem.ptr);

        if (new_size == 0) {
            free(undefined, old_mem, old_align, ret_addr);
            return true;
        } else {
            const new_alloc = pmm.get_allocation_size(@max(new_size, old_align));

            if (new_alloc > old_alloc) {
                return false;
            }

            var curr_alloc = old_alloc;
            while (new_alloc < curr_alloc) {
                pmm.free(@enumFromInt(@intFromEnum(paddr) + curr_alloc / 2), curr_alloc / 2);
                curr_alloc /= 2;
            }

            return true;
        }
    }

    fn free(_: *anyopaque, old_mem: []u8, old_align: u8, _: usize) void {
        const old_alloc = pmm.get_allocation_size(@max(old_mem.len, old_align));
        const paddr = pmm.physaddr_from_ptr(old_mem.ptr);

        pmm.free(paddr, old_alloc);
    }
}{};

pub var gpa: std.heap.GeneralPurposeAllocator(.{ .thread_safe = false }) = .{ .backing_allocator = raw_page_allocator.allocator() };

pub fn alloc_page() !*anyopaque {
    const paddr = try pmm.alloc(1 << 12);
    // todo allocate outside of the big map range but for kernel-mode stuff that isnt too important
    // todo page swapping. again not as important for kernel-mode stuff
    return pmm.ptr_from_physaddr(*anyopaque, paddr);
}

pub fn free_page(ptr: *const anyopaque) void {
    pmm.free(phys_from_virt(@intFromPtr(ptr)), 1 << 12);
}

// fn dump_paging_debug() void {
//     const addr: usize = 0xffffe000fd000000;
//     const p = addr - @as(usize, @bitCast(idmap_base_4lvl));
//     const split: paging.SplitPagingAddr = @bitCast(addr);
//     log.info("address to map: 0x{X:0>16} {b:0>9}:{b:0>9}:{b:0>9}:{b:0>9}:{b:0>9}:{b:0>12}", .{ addr, @as(u9, @bitCast(split.pml4)), split.dirptr, split.directory, split.table, split.page, split.byte });
//     log.info("expect phys addr: {X}:{X:0>3}", .{ p >> 12, p & 4095 });
//     const dirptr = paging.pgtbl.?[split.dirptr].get_phys_addr();
//     log.info("dirptr[{d}] at 0x{X}", .{ split.dirptr, dirptr });
//     const directory = pmm.ptr_from_physaddr(paging.Table(paging.entries.PDPTE), dirptr)[split.directory].get_phys_addr();
//     log.info("directory[{d}] at 0x{X}", .{ split.directory, directory });
//     const direntry = pmm.ptr_from_physaddr(paging.Table(paging.entries.PDE), directory)[split.table];
//     if (direntry.page_size) {
//         log.info("2mb page[{d}] at 0x{X}", .{ split.table, direntry.get_phys_addr() });
//     } else {
//         const table = direntry.get_phys_addr();
//         log.info("table[{d}] at 0x{X}", .{ split.table, table });
//         log.info("4k page[{d}] at 0x{X}", .{ split.page, pmm.ptr_from_physaddr(paging.Table(paging.entries.PTE), table)[split.page].get_phys_addr() });
//     }
// }
