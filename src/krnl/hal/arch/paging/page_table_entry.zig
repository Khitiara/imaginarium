const std = @import("std");
const makeTruncMask = @import("util").masking.makeTruncMask;
const assert = std.debug.assert;

const PhysAddr = @import("cmn").types.PhysAddr;

pub const PageMeta = packed struct(u7) {
    /// if present is false and reserved is true then a page fault to this page should lazily obtain and zero a physical
    /// page. if both present and reserved is false, and the physical address of the page is nonzero then the page is
    /// currently paged out to disk somewhere identified by that address. if the address is zero and both reserved and
    /// present are false then a page fault to this page is always an illegal access to unallocated memory
    reserved: bool,
    _: u6,
};

pub const PML45E = packed struct(u64) {
    present: bool,
    writable: bool,
    user_mode_accessible: bool,
    pwt: bool,
    pcd: bool,
    accessed: bool,
    _ignored1: u6 = 0,
    /// prefer using get/set_phys_addr to access the physical address
    physaddr: u40,
    meta: PageMeta,
    _ignored2: u4 = 0,
    xd: bool,

    const physaddr_mask = makeTruncMask(PML45E, "physaddr");
    pub fn get_phys_addr(self: PML45E) PhysAddr {
        return @enumFromInt(@as(u64, @bitCast(self)) & physaddr_mask);
    }
    pub fn set_phys_addr(self: *PML45E, addr: PhysAddr) void {
        self.physaddr = @truncate(@intFromEnum(addr) >> 12);
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
    /// prefer using get_phys_addr to access the actual physical address.
    /// union will be gb_page if and only if page_size is true
    physaddr: packed union {
        gb_page: packed struct(u51) {
            pat: bool,
            _ignored: u17 = 0,
            physaddr: u22, // must be left shifted 30 to get true addr
            meta: PageMeta,
            protection_key: u4, // ignored if pointing to page directory
        },
        pd_ptr: packed struct(u51) {
            addr: u40, // must be left shifted 12 to get true addr
            meta: PageMeta,
            _ignored2: u4 = 0,
        },
    },
    xd: bool,

    pub fn get_phys_addr(self: PDPTE) PhysAddr {
        if (self.page_size) {
            // 1gb page
            return @enumFromInt(@as(u52, @intCast(self.physaddr.gb_page.physaddr)) << 30);
        } else {
            return @enumFromInt(@as(u52, @intCast(self.physaddr.pd_ptr.addr)) << 12);
        }
    }
    pub fn set_phys_addr(self: *PDPTE, addr: PhysAddr) void {
        if (self.page_size) {
            // 1gb page
            self.physaddr.gb_page.physaddr = @truncate(@intFromEnum(addr) >> 30);
        } else {
            self.physaddr.pd_ptr.addr = @truncate(@intFromEnum(addr) >> 12);
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
        mb_page: packed struct(u51) {
            pat: bool,
            _ignored: u8 = 0,
            physaddr: u31, // must be left shifted 21 to get true addr
            meta: PageMeta,
            protection_key: u4, // ignored if pointing to page table
        },
        pd_ptr: packed struct(u51) {
            addr: u40, // must be left shifted 12 to get true addr
            meta: PageMeta,
            _ignored2: u4 = 0,
        },
    },
    xd: bool,

    pub fn get_phys_addr(self: PDE) PhysAddr {
        if (self.page_size) {
            // 2mb page
            return @enumFromInt(@as(u52, @intCast(self.physaddr.mb_page.physaddr)) << 21);
        } else {
            return @enumFromInt(@as(u52, @intCast(self.physaddr.pd_ptr.addr)) << 12);
        }
    }
    pub fn set_phys_addr(self: *PDE, addr: PhysAddr) void {
        if (self.page_size) {
            // 2mb page
            self.physaddr.mb_page.physaddr = @truncate(@intFromEnum(addr) >> 21);
        } else {
            self.physaddr.pd_ptr.addr = @truncate(@intFromEnum(addr) >> 12);
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
    /// prefer using get/set_phys_addr as it handles the masking in a single operation
    physaddr: u40, // must be left shifted 12 to get true addr
    meta: PageMeta,
    protection_key: u4, // may be ignored if disabled
    xd: bool,

    const physaddr_mask = makeTruncMask(PTE, .physaddr);
    pub fn get_phys_addr(self: PTE) PhysAddr {
        return @enumFromInt(@as(u64, @bitCast(self)) & physaddr_mask);
    }
    pub fn set_phys_addr(self: *PTE, addr: PhysAddr) void {
        self.physaddr = @truncate(@intFromEnum(addr) >> 12);
    }
};

test {
    _ = @as(PML45E, @bitCast(@as(u64, 0)));
    _ = @as(PDPTE, @bitCast(@as(u64, 0)));
    _ = @as(PDE, @bitCast(@as(u64, 0)));
    _ = @as(PTE, @bitCast(@as(u64, 0)));

    _ = PML45E.get_phys_addr;
    _ = PDPTE.get_phys_addr;
    _ = PDE.get_phys_addr;
    _ = PTE.get_phys_addr;

    _ = PML45E.set_phys_addr;
    _ = PDPTE.set_phys_addr;
    _ = PDE.set_phys_addr;
    _ = PTE.set_phys_addr;
}
