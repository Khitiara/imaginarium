const ext = @import("util").extern_address;
const memory = @import("../../../memory.zig");
const std = @import("std");

const stage1_base: isize = @intFromPtr(ext("__base"));
const kernel_phys_end: usize = @intFromPtr(ext("__kernel_phys_end"));

var phys_addr_width: u8 = undefined;
var free_roots: []usize = undefined;
var phys_mapping_base: isize = stage1_base;
var phys_mapping_limit: usize = 1 << 31; // 2G mapped by bootelf, will be reinitialized once paging is set up
var pmm_sizes:[]const usize = undefined;

const pmm_sizes_global = blk: {
    var shift = 12;
    var sizes: []const usize = &[0]usize{};

    while (shift < @bitSizeOf(usize) - 3) : (shift += 1) {
        sizes = sizes ++ [1]usize{1 << shift};
    }

    break :blk sizes;
};

var free_roots_global = [_]usize{0} ** pmm_sizes_global.len;

pub fn init(paddrwidth: u8, memmap: []memory.MemoryMapEntry) void {
    phys_addr_width = paddrwidth;
    free_roots = free_roots_global[0..(phys_addr_width - 12)];
    pmm_sizes = pmm_sizes_global[0..(phys_addr_width - 12)];
    for (memmap) |entry| {
        // only accept blocks that can fit wholly in our memory limit. a bit restrictive but its hard to reason
        // about correctness and how to free the rest when we do have the paging set up to accept the rest
        if (entry.type == .normal and entry.base + entry.size < phys_mapping_limit) {
            free(entry.base, entry.size);
        }
    }
}

pub fn enlarge_mapped_physical(memmap: []memory.MemoryMapEntry, new_base: isize) void {
    phys_mapping_base = new_base;
    const old_limit = phys_mapping_limit;
    phys_mapping_limit = 1 << phys_addr_width;
    for (memmap) |entry| {
        if (entry.type == .normal and entry.base + entry.size >= old_limit) {
            free(entry.base, entry.size);
        }
    }
}

fn alloc_impl(idx: usize) error{OutOfMemory}!usize {
    if (free_roots[idx] == 0) {
        if (idx + 1 >= pmm_sizes.len) {
            return error.OutOfMemory;
        }

        // no free roots at this size, so split up a root from the next size up (recursively)
        var next = try alloc_impl(idx + 1);
        var next_size = pmm_sizes[idx + 1];
        const curr_size = pmm_sizes[idx];

        while (next_size > curr_size) {
            free_impl(next, idx);
            next += curr_size;
            next_size -= curr_size;
        }

        return next;
    } else {
        const addr = free_roots[idx];
        free_roots[idx] = @as(*const usize, @ptrFromInt(addr + phys_mapping_base)).*;
        return addr;
    }
}

fn free_impl(phys_addr: usize, index: usize) void {
    @as(*usize, @ptrFromInt(phys_addr + phys_mapping_base)).* = free_roots[index];
    free_roots[index] = phys_addr;
    return true;
}

pub fn alloc(len: usize) !usize {
    for (pmm_sizes, 0..) |sz, idx| {
        if (sz >= len) {
            return alloc_impl(idx);
        }
    }
    return error.PhysicalAllocationTooBig;
}

pub fn free(phys_addr: usize, len: usize) void {
    var sz = len;
    var a = phys_addr;
    outer: while (sz > 0) {
        var it = std.mem.reverseIterator(pmm_sizes);
        var idx = pmm_sizes.len - 1;
        while (it.next()) |s| : (idx -= 1) {
            if (sz >= s and std.mem.isAligned(phys_addr, s)) {
                free_impl(phys_addr, idx);
                sz -= s;
                a += s;
                continue :outer;
            }
        }
    }
}
