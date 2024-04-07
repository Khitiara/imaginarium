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

pub const RegionType = enum(u32) {
    normal = 1,
    reserved,
    acpi_reclaimable,
    acpi_nvs,
    unusable,
    disabled,
    persistent_memory,
    _,
};

pub const ExtendedAddressRangeAttributes = packed struct(u32) {
    _reserved1: u1 = 1,
    _reserved2: u2 = 0,
    address_range_error_log: bool,
    _reserved3: u28 = 0,
};

pub const MemoryMapEntry = extern struct {
    base: PhysicalAddress,
    size: usize,
    type: RegionType,
    attributes: ExtendedAddressRangeAttributes,
};
