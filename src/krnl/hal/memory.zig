const std = @import("std");

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
    base: usize,
    size: usize,
    type: RegionType,
    attributes: ExtendedAddressRangeAttributes,
};
