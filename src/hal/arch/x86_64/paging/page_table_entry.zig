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
    /// prefer using get/setPhysAddr to access the physical address
    physaddr: u40,
    _ignored2: u11 = 0,
    xd: bool,

    const physaddr_mask = makeTruncMask(PML45E, .physaddr);
    pub fn getPhysAddr(self: PML45E) u64 {
        return @as(u64, @bitCast(self)) & physaddr_mask;
    }
    pub fn setPhysAddr(self: *PML45E, addr: u64) void {
        @as(*u64, @ptrCast(self)).* |= (addr & physaddr_mask);
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
    /// prefer using getPhysAddr to access the actual physical address.
    /// union will be gb_page if and only if page_size is true
    physaddr: packed union {
        gb_page: packed struct(u51) {
            pat: bool,
            _ignored: u17 = 0,
            physaddr: u22, // must be left shifted 30 to get true addr
            _ignored3: u7 = 0,
            protection_key: u4, // ignored if pointing to page directory
        },
        pd_ptr: packed struct(u51) {
            addr: u40, // must be left shifted 12 to get true addr
            _ignored3: u11 = 0,
        },
    },
    xd: bool,

    pub fn getPhysAddr(self: PDPTE) u52 {
        if (self.page_size) {
            // 1gb page
            const offset = @bitOffsetOf(PDPTE, "physaddr") + @bitOffsetOf(TagPayloadByName(@TypeOf(self.physaddr), "gb_page"), "physaddr");
            comptime assert(offset == 30);
            const mask = ((1 << 31) - 1) << offset;
            return @as(u64, @bitCast(self)) & mask;
        } else {
            const mask = ((1 << 40) - 1) << @bitOffsetOf(PDE, "physaddr");
            return @as(u64, @bitCast(self)) & mask;
        }
    }
    pub fn setPhysAddr(self: *PDPTE, addr: u64) void {
        if (self.page_size) {
            // 2mb page
            const offset = @bitOffsetOf(PDPTE, "physaddr") + @bitOffsetOf(TagPayloadByName(@TypeOf(self.physaddr), "gb_page"), "physaddr");
            comptime assert(offset == 21);
            const mask = ((1 << 31) - 1) << offset;
            @as(*u64, @ptrCast(self)).* |= addr & mask;
        } else {
            const mask = ((1 << 40) - 1) << @bitOffsetOf(PDPTE, "physaddr");
            @as(*u64, @ptrCast(self)).* |= addr & mask;
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
        gb_page: packed struct(u51) {
            pat: bool,
            _ignored: u8 = 0,
            physaddr: u31, // must be left shifted 21 to get true addr
            _ignored2: u7 = 0,
            protection_key: u4, // ignored if pointing to page table
        },
        pd_ptr: packed struct(u51) {
            addr: u40, // must be left shifted 12 to get true addr
            _ignored: u11 = 0,
        },
    },
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
    pub fn setPhysAddr(self: *PDE, addr: u64) void {
        if (self.page_size) {
            // 2mb page
            const offset = @bitOffsetOf(PDE, "physaddr") + @bitOffsetOf(TagPayloadByName(@TypeOf(self.physaddr), "gb_page"), "physaddr");
            comptime assert(offset == 21);
            const mask = ((1 << 31) - 1) << offset;
            @as(*u64, @ptrCast(self)).* |= addr & mask;
        } else {
            const mask = ((1 << 40) - 1) << @bitOffsetOf(PDE, "physaddr");
            @as(*u64, @ptrCast(self)).* |= addr & mask;
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
    /// prefer using get/setPhysAddr as it handles the masking in a single operation
    physaddr: u40, // must be left shifted 12 to get true addr
    _ignored3: u7 = 0,
    protection_key: u4, // may be ignored if disabled
    xd: bool,

    const physaddr_mask = makeTruncMask(PTE, .physaddr);
    pub fn getPhysAddr(self: PTE) u64 {
        return @as(u64, @bitCast(self)) & physaddr_mask;
    }
    pub fn setPhysAddr(self: *PTE, addr: u64) void {
        @as(*u64, @ptrCast(self)).* |= (addr & physaddr_mask);
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

    _ = PML45E.setPhysAddr;
    _ = PDPTE.setPhysAddr;
    _ = PDE.setPhysAddr;
    _ = PTE.setPhysAddr;
}
