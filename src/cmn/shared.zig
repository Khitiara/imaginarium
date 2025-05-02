const std = @import("std");

pub const BootInfo = struct {};

pub var boot_info: BootInfo linksection(".shared") = .{};
var boot_info_buf: [256]u8 = undefined;

pub var boot_info_fba = std.heap.FixedBufferAllocator.init(boot_info_buf);
pub const boot_info_alloc = boot_info_fba.allocator();
