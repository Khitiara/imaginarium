//! the kernel memory manager

pub const mminit = @import("mminit.zig");

const std = @import("std");
const arch = @import("../arch/arch.zig");

pub inline fn pages_spanned(start: usize, len: usize) usize {
    return ((start & comptime (std.mem.page_size - 1)) + len) / std.mem.page_size;
}

pub inline fn flush_local_tlb() void {
    arch.control_registers.write(.cr3, arch.control_registers.read(.cr3));
}