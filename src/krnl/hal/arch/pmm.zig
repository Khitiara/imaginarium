// this PMM implementation is derived from the one in Florence
// the original implementation as of the creation of this version may be found at the following address:
//
// https://github.com/FlorenceOS/Florence/blob/aaa5a9e568197ad24780ec9adb421217530d4466/subprojects/flork/src/memory/pmm.zig
//
//
// this is effectively a buddy list allocation system implemented via a singly linked list stored in the free blocks
//
// the PMM uses a set of singly linked lists (used as LIFO stacks) of free blocks, one list for each power-of-two block
// size between 4096 and the maximum block size supported by the physical address width of the system
// all addresses in the lists are stored as physical addresses and the head addresses are stored in a global array
// with the next pointers being stored as physical addresses in the first addressable usize of each block
// blocks must always be aligned and allocations of less than one 4K page are not supported.
// the pmm accesses physical addresses by assuming that all physical addresses have been sequentially mapped
// starting at a known base address, with the linear address base + n mapped to the nth byte of physical memory
// when allocating smaller blocks, the allocation algorithm may allocate a large block and split it into smaller blocks
// while each block may only generally be split into two halves by the nature of the power-of-two sizes,
// the only part of the pmm implementation that assumes this is an optimization whereby the alloc function
// uses the cli instruction to do an efficient log_2 of the requested allocation size and thereby skip some iterations
// of a loop to select the index into the free roots array from the requested length.
//
// this implementation deviates from the original implementation as of 2024-04-12 (in addition to the above-mentioned
// optimization) insofar as it:
//
// 1. (WIP) provides a routine for defragmenting allocations, merging consecutive free blocks into one larger block
// 2. permits changing the sequential-mapping base address after initialization to permit switching from the initial
//      bootloader-provided memory layout to a virtual memory layout managed by the kernel
// 3. only initializes the first 2G of physical memory at first (minus the portion in which the bootloader and kernel
//      structures are located)
// 4. permits adding the rest of physical memory later once the appropriate kernel structures are available to use
//      higher physical memory (general paging, a page fault handler, etc)

const ext = @import("util").extern_address;
const std = @import("std");
const cmn = @import("cmn");
const PhysAddr = cmn.types.PhysAddr;

// the base virtual address of the initial memory layout. should always be -2G but only set it once in the linkerscript
pub var kernel_size: usize = undefined;

// the number of physical address bits
var phys_addr_width: u8 = undefined;

// the base address and length of the identity mapped region.
// starts off as 2G mapped at stage1_base by bootelf;
// once the pmm is set up and we can allocate page tables
// the vmm will lazily identity map all of physical memory at a new virtual base address
pub var phys_mapping_base: isize = undefined;
var phys_mapping_base_unsigned: usize = undefined;
var phys_mapping_limit: usize = 1 << 31;

// the set of physical sizes we can maybe use. the set of powers of 2 from 1 << 12 (4096) to 1 << 52 (a very big number) inclusive
const pmm_sizes_global = blk: {
    var sizes: [41]usize = [_]usize{0} ** 41;
    for (12..53, 0..) |shift, i| {
        sizes[i] = 1 << shift;
    }
    break :blk sizes;
};

// the set of physical sizes we can actually use. a slice of pmm_sizes_global up to the actual physical address
// width as reported by cpuid
var pmm_sizes: []const usize = undefined;

// the address of the first free root of a given size (sizes from pmm_sizes)
export var free_roots = [_]PhysAddr{.nul} ** pmm_sizes_global.len;

pub var max_phys_mem: usize = 0;

const log = std.log.scoped(.pmm);

// initialize the pmm. takes the physical address width and the memory map
pub fn init(paddrwidth: u8, memmap: []cmn.memmap.Entry) void {
    phys_mapping_base_unsigned = @intFromPtr(@extern(*u64, .{ .name = "__base__" }));
    phys_mapping_base = @bitCast(phys_mapping_base_unsigned);
    log.debug("initial physical mapping base 0x{X}", .{phys_mapping_base_unsigned});
    kernel_size = std.mem.alignForwardLog2(@intFromPtr(@extern(*u64, .{ .name = "__kernel_end__" })) - phys_mapping_base_unsigned, 24);
    log.debug("kernel physical end 0x{X}", .{kernel_size});
    // set our global physical address width
    phys_addr_width = paddrwidth;
    // slice our arrays
    pmm_sizes = pmm_sizes_global[0..(phys_addr_width - 12)];

    // go through the memory map and mark free as appropriate.
    // physical address 0 through kernel_phys_end are always considered not-free as they cover the region used
    // by our bootloader (bootelf) and in which bootelf and the stage1 kernel are mapped
    // we only mark free kernel_phys_end through 2G at the start. once the vmm and page fault handler are set up
    // we can switch to a larger region. the identity mapping will change as well once the vmm is set up but
    // the identity mapped region is mapped lazily by the vmm through the page fault handler
    for (memmap) |entry| {
        if (entry.type == .normal) {
            var base = @intFromEnum(entry.base);
            var size = entry.size;
            const end = base + size;
            if (end > max_phys_mem)
                max_phys_mem = end;
            // if the block is wholly within where the kernel is mapped then it should never be free
            if (end < kernel_size) {
                log.debug("skipping 0x{X}..0x{X} as it is wholly within space already reserved by the kernel", .{ base, end });
                continue;
            }
            // only accept blocks that can fit wholly in our memory limit. a bit restrictive but its hard to reason
            // about correctness and how to free the rest when we do have the paging set up to accept the rest
            if (end > phys_mapping_limit) {
                log.debug("skipping 0x{X}..0x{X} as it exceeds the physical mapping limit 0x{X}", .{ base, end, phys_mapping_limit });
                continue;
            }
            // if the block covers the boundary of the kernel then only free the portion after the kernel
            if (base < kernel_size) {
                const diff = kernel_size - base;
                log.debug("adjusting 0x{X}..0x{X} forward 0x{X} bytes to avoid initial kernel block", .{ base, end, diff });
                base = kernel_size;
                size -= diff;
            }
            log.debug("marking 0x{X}..0x{X} (0x{X} bytes)", .{ base, end, size });
            // any alignment and other nonsense the bios throws at us gets handled in mark_free
            mark_free(@enumFromInt(base), size);
        }
    }
}

// switch to a complete identity map at a new base virtual address.
// this allows the use of the full physical memory not just the first 2G that bootelf maps
// current plan is to map all of physmem at -1 << 45 (ffff_e..._...._....)
pub fn enlarge_mapped_physical(memmap: []cmn.memmap.Entry, new_base: isize) void {
    phys_mapping_base_unsigned = @bitCast(new_base);
    phys_mapping_base = new_base;
    const old_limit = phys_mapping_limit;
    phys_mapping_limit = @as(usize, 1) << @intCast(phys_addr_width);
    for (memmap) |entry| {
        // we already mapped entries which are wholly within our old limits
        if (entry.type == .normal and @intFromEnum(entry.base) + entry.size >= old_limit) {
            // all the alignment and other nonsense is handled by mark_free
            log.debug("marking 0x{X}..0x{X} (0x{X} bytes)", .{ entry.base, @intFromEnum(entry.base) + entry.size, entry.size });
            mark_free(entry.base, entry.size);
        }
    }
}

// turns a physical address into a pointer by way of the identity mapped region
// before enlarge_mapped_physical is called the returend pointers should not be saved
pub fn ptr_from_physaddr(Ptr: type, paddr: PhysAddr) Ptr {
    // if the phys addr is 0 and the pointer is optional then its null. used mainly in the pmm to mark the end of the
    // free block lists
    if (@as(std.builtin.TypeId, @typeInfo(Ptr)) == .optional and paddr == .nul) {
        return null;
    }
    return @ptrFromInt(@intFromEnum(paddr) +% phys_mapping_base_unsigned);
}

pub fn physaddr_from_ptr(ptr: anytype) PhysAddr {
    return @enumFromInt(@intFromPtr(ptr) -% phys_mapping_base_unsigned);
}

// allocate a block from physical memory by index
// the size of the region is pmm_sizes[idx] but working by index is easier
fn alloc_impl(idx: usize) error{OutOfMemory}!PhysAddr {
    // check if there is a free root available at the requested size
    if (free_roots[idx] == .nul) {
        // no block of the given size is available

        // is there another larger size to allocate and split?
        if (idx + 1 >= pmm_sizes.len) {
            return error.OutOfMemory;
        }

        // no free roots at this size, so split up a root from the next size up (recursively)
        // start by allocating the larger block
        var next = try alloc_impl(idx + 1);
        // also grab the size of that larger block from pmm_sizes
        var next_size = pmm_sizes[idx + 1];

        // treat the large block we got as an array of smaller blocks
        // grab the size we want from pmm_sizes
        const curr_size = pmm_sizes[idx];

        // loop through and free blocks of our size until we have only one left
        // this should divide evenly because powers of two, and in fact should only go through one iteration
        while (next_size > curr_size) {
            free_impl(next, idx);
            next = @enumFromInt(@intFromEnum(next) + curr_size);
            next_size -= curr_size;
        }

        // return the last block of our size in the list of blocks
        return next;
    } else {
        // there is a free root available at our size.
        // each free root is a singly linked list with the next free address stored in the "free" memory
        // since we're the kernel free memory just means memory owned by the pmm and allocated memory
        // is just memory owned by some other component
        const addr = free_roots[idx];
        // store the next address in the free roots over the one we allocated
        free_roots[idx] = ptr_from_physaddr(*const PhysAddr, addr).*;
        return addr;
    }
}

// free by index into free_roots rather than by size
fn free_impl(phys_addr: PhysAddr, index: usize) void {
    // TODO: if enough contiguous blocks are free then free a larger block instead
    ptr_from_physaddr(*PhysAddr, phys_addr).* = free_roots[index];
    free_roots[index] = phys_addr;
}

// allocate a block of at least len bytes
pub fn alloc(len: usize) !PhysAddr {
    // log2_ceil of the length - 12 indexes into pmm_sizes the smallest block size strictly larger than len
    const idx = std.math.log2_int_ceil(usize, len) - 12;
    if (idx >= pmm_sizes.len) {
        return error.physical_allocation_too_large;
    }
    // forward the actual allocation to alloc_impl
    const p = try alloc_impl(idx);
    @memset(ptr_from_physaddr([*]u8, p)[0..len], undefined);
    return p;
}

pub fn get_allocation_size(size: usize) usize {
    const idx = std.math.log2_int_ceil(usize, size) -| 12;
    return pmm_sizes[idx];
}

// free an allocated block which was at least len bytes
pub fn free(phys_addr: PhysAddr, len: usize) void {
    // the physical addresses we return should always be page-aligned
    // and ideally so will whatever the memmap gives us to free here
    if (!std.mem.isAligned(@intFromEnum(phys_addr), pmm_sizes[0])) {
        @panic("unaligned address to free");
    }

    // log2_ceil of the length - 12 indexes into pmm_sizes the smallest block size strictly larger than len.
    // this is the same computation as in alloc so should match the size we actually gave
    const idx = std.math.log2_int_ceil(usize, len) - 12;
    free_impl(phys_addr, idx);
}

// mark a new memory block as free. generally called with entries from the bios or uefi memory map
fn mark_free(phys_addr: PhysAddr, len: usize) void {
    var sz: usize = len;

    // the bios sucks i give up so for this we align the start of the block forward to match our smallest block size
    var a: PhysAddr = @enumFromInt(std.mem.alignForwardLog2(@intFromEnum(phys_addr), 12));
    // if we aligned forward then shrink the size accordingly so we dont reach into reserved ranges
    sz -= @bitCast(@intFromEnum(a) - @intFromEnum(phys_addr));
    // and align the size backward to a multiple of our smallest block size because the bios still sucks
    sz = std.mem.alignBackward(usize, sz, pmm_sizes[0]);

    // loop to progressively shrink the block to be freed.
    // each free must be page-aligned in both size and address
    outer: while (sz != 0) {
        // we obviously cant free a block bigger than sz and the log2 ought to trim out extra bits
        var idx = @min(pmm_sizes.len - 1, std.math.log2_int(usize, sz) - 12) + 1;
        while (idx > 0) {
            idx -= 1;
            const s = pmm_sizes[idx];
            // find the largest size that is no greater than the amount to free and which is aligned
            // the sz >= s case should be covered by the log2 bit above but leave it in for now just in case
            if (sz >= s and std.mem.isAligned(@intFromEnum(a), s)) {
                // free the biggest block we can fit aligned in the newly freed region
                free_impl(a, idx);
                // adjust the address and size to remove the freed chunk and restart
                sz -= s;
                a = @enumFromInt(@intFromEnum(a) + s);
                continue :outer;
            }
        }
        // guards up top cover this case
        unreachable;
    }
}

// fn defrag() void {
//     for (free_roots, 0..) |*root, i| {
//         sort_free_root(root);
//         merge_blocks(root, i);
//     }
// }
//
// fn merge_blocks(root: *usize, index: usize) void {
//     if (index + 1 > pmm_sizes.len)
//         return;
//     var p: ?*usize = root;
//     while (p != null) {
//         const qa = p.*;
//         const q = ptr_from_physaddr(?*usize, qa);
//         if (q != null and q.* != 0 and q.* - qa == pmm_sizes[index]) {
//             free_impl(qa, index + 1);
//             p.* = ptr_from_physaddr(*usize, q.*).*;
//             p = ptr_from_physaddr(?*usize, p.*);
//         }
//     }
// }
//
// // https://www.chiark.greenend.org.uk/~sgtatham/algorithms/listsort.html
// // no i dont really understand this that well
// fn sort_free_root(root: *usize) void {
//     var k: usize = 1;
//     var l: usize = 0;
//     var l_tail = &l;
//     var merges: usize = 0;
//     while (merges != 1) {
//         merges = 0;
//         var psize = 0;
//         var qsize = k;
//         var p: *?usize = ptr_from_physaddr(?*usize, root.head);
//         var q: *?usize = undefined;
//         while (p != null) {
//             merges += 1;
//             q = p;
//             while (psize < k) {
//                 q = ptr_from_physaddr(?*usize, q.*);
//                 if (q == null) {
//                     break;
//                 }
//                 psize += 1;
//             }
//             while (psize > 0 or (qsize > 0 and q != null)) {
//                 if (q != null and qsize > 0 and (psize == 0 or q.* < p.*)) {
//                     l_tail.* = @intFromPtr(q) - phys_mapping_base;
//                     l_tail = q;
//                     q = ptr_from_physaddr(?*usize, q.*);
//                     qsize -= 1;
//                 } else if (psize > 0) {
//                     l_tail.* = @intFromPtr(p) - phys_mapping_base;
//                     l_tail = p;
//                     p = ptr_from_physaddr(?*usize, p.*);
//                     psize -= 1;
//                 } else {
//                     break;
//                 }
//             }
//
//             p = q;
//             k *= 2;
//         }
//     }
//     root = l;
// }
