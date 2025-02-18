const pte = @import("pte.zig");
const pfmdb = @import("pfmdb.zig");
const map = @import("map.zig");

pub inline fn is_address_present(addr: usize) bool {
    return map.pxe_from_addr(addr).unknown.present and map.ppe_from_addr(addr).unknown.present and map.pde_from_addr(addr).unknown.present and map.pte_from_addr(addr).unknown.present;
}

pub const PATBits = packed union {
    bits: packed struct(u3) {
        pwt: bool,
        pcd: bool,
        pat: bool,
    },
    typ: MemoryCacheType,
};

pub const MemoryCacheType = enum(u3) {
    write_back,
    write_through,
    uncached_minus,
    uncached,
    write_protect,
    write_combine,
    _,
};