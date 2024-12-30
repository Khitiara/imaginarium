//! the kernel memory manager

pub const mminit = @import("mminit.zig");

const std = @import("std");

pub inline fn pages_spanned(start: usize, len: usize) usize {
    return ((start & comptime (std.mem.page_size - 1)) + len) / std.mem.page_size;
}
