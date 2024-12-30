const std = @import("std");

const PhysAddr = @import("types.zig").PhysAddr;

pub const RegionType = enum(u32) {
    usable = 1,
    reserved,
    acpi_reclaimable,
    acpi_nvs,
    bad_memory,
    disabled,
    persistent,
};

pub const ExtendedAddressRangeAttributes = packed struct(u32) {
    _reserved1: u1 = 1,
    _reserved2: u2 = 0,
    address_range_error_log: bool,
    _reserved3: u28 = 0,
};

pub const Entry = extern struct {
    base: usize,
    length: usize,
    kind: RegionType,
    attributes: ExtendedAddressRangeAttributes,
};
