const checksum = @import("util").checksum;
const sdt = @import("sdt.zig");
const std = @import("std");

pub const rsd_ptr_sig: *const [8]u8 = "RSD PTR ";

const ptr_from_physaddr = @import("../arch.zig").ptr_from_physaddr;

pub const Rsdp1 = extern struct {
    signature: [8]u8,
    checksum: u8,
    oem_id: [6]u8,
    revision: u8,
    rsdt_addr: u32,

    pub usingnamespace checksum.add_checksum(Rsdp1, *align(1) const Rsdp1, false);
};

pub const Rsdp2 = extern struct {
    v1: Rsdp1,
    length: u32,
    xsdt_addr: u64 align(4),
    checksum: u8,
    reserved: [3]u8,

    pub usingnamespace checksum.add_checksum(Rsdp1, *align(1) const Rsdp2, false);
};

pub const RsdpError = error{
    unrecognized_version,
    table_not_found,
    xsdt_on_32bit,
    rsdp_not_found,
} || checksum.ChecksumErrors;

pub const RsdpInfo = struct {
    oem_id: [6]u8,
    table_addr: *align(4) const anyopaque,
    expect_signature: sdt.Signature,

    pub fn from_rsdp(rsdp: Rsdp) RsdpInfo {
        switch (rsdp) {
            .v1 => |v1| return .{ .oem_id = v1.oem_id, .table_addr = ptr_from_physaddr(*align(4) const anyopaque, v1.rsdt_addr), .expect_signature = .RSDT },
            .v2 => |v2| return .{ .oem_id = v2.v1.oem_id, .table_addr = ptr_from_physaddr(*align(4) const anyopaque, v2.xsdt_addr), .expect_signature = .XSDT },
        }
    }
};

pub const Rsdp = union(enum) {
    v1: *align(1) const Rsdp1,
    v2: *align(1) const Rsdp2,

    pub fn fetch_from_pointer(ptr: *const anyopaque) !Rsdp {
        const v1_ptr: *align(1) const Rsdp1 = @ptrCast(ptr);
        try v1_ptr.verify_checksum();
        switch (v1_ptr.revision) {
            0 => return .{ .v1 = v1_ptr },
            2 => {
                if (@import("builtin").target.cpu.arch == .x86) return error.xsdt_on_32bit;
                const v2_ptr: *align(1) const Rsdp2 = @ptrCast(ptr);
                try v2_ptr.verify_checksum();
                return .{ .v2 = v2_ptr };
            },
            else => return error.unrecognized_version,
        }
    }

    pub fn compute_checksum(self: *Rsdp) u8 {
        switch (self) {
            inline else => |this| return this.compute_checksum(),
        }
    }

    pub fn verify_checksum(self: *Rsdp) checksum.ChecksumErrors!void {
        switch (self) {
            inline else => |this| return this.verify_checksum(),
        }
    }
};

const RsdpAlignedPrologue = extern struct {
    signature: [8]u8,
    _padding: [8]u8,
};

inline fn rsdp_search(region: []const u8) !?Rsdp {
    const slice = std.mem.bytesAsSlice(RsdpAlignedPrologue, region);
    for (slice) |*hay| {
        if (std.mem.eql(u8, &hay.signature, rsd_ptr_sig)) {
            return try Rsdp.fetch_from_pointer(hay);
        }
    }
    return null;
}

pub fn locate_rsdp_bios() !Rsdp {
    const ebda_addr = ptr_from_physaddr(*const u16, 0x40E).*;
    const ebda = ptr_from_physaddr(*const [0x400]u8, ebda_addr << 4);
    if (try rsdp_search(ebda)) |rsdp| {
        return rsdp;
    }
    if (try rsdp_search(ptr_from_physaddr(*const [0x20000]u8, 0xE0000))) |rsdp| {
        return rsdp;
    }
    return error.rsdp_not_found;
}
