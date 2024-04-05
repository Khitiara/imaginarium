const std = @import("std");

pub const VirtualRegion = enum(i20) {
    RebasedPhysicalMem = -2,
    KernelPrimaryRegion = -1,
    _,
};

const VirtualSubAddress = std.meta.Int(.unsigned, @bitSizeOf(usize) - @bitSizeOf(VirtualRegion));

pub const VirtualAddress = packed struct(isize) {
    address: VirtualSubAddress,
    region: VirtualRegion,
};

pub const PhysicalAddress = if(@import("config").use_signed_physaddr) isize else usize;