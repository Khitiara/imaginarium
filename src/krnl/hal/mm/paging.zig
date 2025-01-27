const pte = @import("pte.zig");
const pfmdb = @import("pfmdb.zig");
const map = @import("map.zig");

pub inline fn is_address_present(addr: usize) bool {
    return map.pxe_from_addr(addr).unknown.present and map.ppe_from_addr(addr).unknown.present and map.pde_from_addr(addr).unknown.present and map.pte_from_addr(addr).unknown.present;
}