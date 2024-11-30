const checksum = @import("util").checksum;
const sdt = @import("sdt.zig");
const std = @import("std");

pub const rsd_ptr_sig: *const [8]u8 = "RSD PTR ";

const ptr_from_physaddr = @import("../arch/arch.zig").ptr_from_physaddr;
const physaddr_from_ptr = @import("../arch/arch.zig").physaddr_from_ptr;

pub const RsdpError = error{
    unrecognized_version,
    table_not_found,
    xsdt_on_32bit,
    NotFound,
} || checksum.ChecksumErrors;

const RsdpAlignedPrologue = extern struct {
    signature: [8]u8,
    _padding: [8]u8,
};

inline fn rsdp_search(region: []align(4) const u8) ?*align(4)const anyopaque {
    const slice = std.mem.bytesAsSlice(RsdpAlignedPrologue, region);
    for (slice) |*hay| {
        if (std.mem.eql(u8, &hay.signature, rsd_ptr_sig)) {
            return hay;
        }
    }
    return null;
}

const PhysAddr = @import("cmn").types.PhysAddr;

fn locate_rsdp_bios() !PhysAddr {
    const ebda_addr = ptr_from_physaddr(*const u16, @enumFromInt(0x40E)).*;
    const ebda = ptr_from_physaddr(*align(4) const [0x400]u8, @enumFromInt(ebda_addr << 4));
    if (rsdp_search(ebda)) |rsdp| {
        return physaddr_from_ptr(rsdp);
    }
    if (rsdp_search(ptr_from_physaddr(*align(4) const [0x20000]u8, @enumFromInt(0xE0000)))) |rsdp| {
        return physaddr_from_ptr(rsdp);
    }
    return error.NotFound;
}

const zuid = @import("zuid");

fn locate_rsdp_efi() !PhysAddr {
    const sys = std.os.uefi.system_table;
    const tbls = sys.configuration_table[0..sys.number_of_table_entries];
    for (tbls) |t| {
        if (t.vendor_guid.eql(std.os.uefi.tables.ConfigurationTable.acpi_20_table_guid)) {
            return t.vendor_table;
        }
    }
    for (tbls) |t| {
        if (t.vendor_guid.eql(std.os.uefi.tables.ConfigurationTable.acpi_10_table_guid)) {
            return t.vendor_table;
        }
    }
    return error.NotFound;
}

pub const locate_rsdp: fn () RsdpError!PhysAddr = if (@import("builtin").os.tag == .uefi or !@import("config").rsdp_search_bios) locate_rsdp_efi else locate_rsdp_bios;
