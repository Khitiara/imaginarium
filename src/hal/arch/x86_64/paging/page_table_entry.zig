const std = @import("std");
const makeTruncMask = @import("util").masking.makeTruncMask;
const TagPayloadByName = std.meta.TagPayloadByName;
const assert = std.debug.assert;

pub const PML45E = packed struct(u64) {
    present: bool,
    writable: bool,
    user_mode_accessible: bool,
    pwt: bool,
    pcd: bool,
    accessed: bool,
    _ignored1: u6 = 0,
    physaddr: u40,
    _ignored2: u11 = 0,
    xd: bool,

    const physaddr_mask = makeTruncMask(PML45E, .physaddr);
    pub fn getPhysAddr(self: PML45E) u64 {
        return @as(u64, @bitCast(self)) & physaddr_mask;
    }
};

pub const PDPTE = packed struct(u64) {
    present: bool,
    writable: bool,
    user_mode_accessible: bool,
    pwt: bool,
    pcd: bool,
    accessed: bool,
    dirty: bool,
    page_size: bool,
    global: bool,
    _ignored1: u3 = 0,
    physaddr: packed union {
        gb_page: packed struct(u40) {
            pat: bool,
            _ignored: u17 = 0,
            physaddr: u22, // must be left shifted 30 to get true addr
        },
        pd_ptr: u40, // must be left shifted 12 to get true addr
    },
    _ignored3: u7 = 0,
    protection_key: u4, // ignored if pointing to page directory
    xd: bool,

    pub fn getPhysAddr(self: PDPTE) u52 {
        if (self.page_size) {
            // 1gb page
            const offset = @bitOffsetOf(PDE, "physaddr") + @bitOffsetOf(TagPayloadByName(@TypeOf(self.physaddr), "gb_page"), "physaddr");
            comptime assert(offset == 30);
            const mask = ((1 << 31) - 1) << offset;
            return @as(u64, @bitCast(self)) & mask;
        } else {
            const mask = ((1 << 40) - 1) << @bitOffsetOf(PDE, "physaddr");
            return @as(u64, @bitCast(self)) & mask;
        }
    }
};

pub const PDE = packed struct(u64) {
    present: bool,
    writable: bool,
    user_mode_accessible: bool,
    pwt: bool,
    pcd: bool,
    accessed: bool,
    dirty: bool,
    page_size: bool,
    global: bool,
    _ignored1: u3 = 0,
    physaddr: packed union {
        gb_page: packed struct(u40) {
            pat: bool,
            _ignored: u8 = 0,
            physaddr: u31, // must be left shifted 21 to get true addr
        },
        pd_ptr: u40, // must be left shifted 12 to get true addr
    },
    _ignored3: u7 = 0,
    protection_key: u4, // ignored if pointing to page table
    xd: bool,

    pub fn getPhysAddr(self: PDE) u52 {
        if (self.page_size) {
            // 2mb page
            const offset = @bitOffsetOf(PDE, "physaddr") + @bitOffsetOf(TagPayloadByName(@TypeOf(self.physaddr), "gb_page"), "physaddr");
            comptime assert(offset == 21);
            const mask = ((1 << 31) - 1) << offset;
            return @as(u64, @bitCast(self)) & mask;
        } else {
            const mask = ((1 << 40) - 1) << @bitOffsetOf(PDE, "physaddr");
            return @as(u64, @bitCast(self)) & mask;
        }
    }
};

pub const PTE = packed struct(u64) {
    present: bool,
    writable: bool,
    user_mode_accessible: bool,
    pwt: bool,
    pcd: bool,
    accessed: bool,
    dirty: bool,
    pat: bool,
    global: bool,
    _ignored1: u3 = 0,
    physaddr: u40, // must be left shifted 12 to get true addr
    _ignored3: u7 = 0,
    protection_key: u4, // ignored if pointing to page directory
    xd: bool,

    const physaddr_mask = makeTruncMask(PTE, .physaddr);
    pub fn getPhysAddr(self: PTE) u64 {
        return @as(u64, @bitCast(self)) & physaddr_mask;
    }
};

test {
    _ = @as(PML45E, @bitCast(@as(u64, 0)));
    _ = @as(PDPTE, @bitCast(@as(u64, 0)));
    _ = @as(PDE, @bitCast(@as(u64, 0)));
    _ = @as(PTE, @bitCast(@as(u64, 0)));

    _ = PML45E.getPhysAddr;
    _ = PDPTE.getPhysAddr;
    _ = PDE.getPhysAddr;
    _ = PTE.getPhysAddr;
}
