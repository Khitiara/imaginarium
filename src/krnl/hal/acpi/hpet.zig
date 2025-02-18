const std = @import("std");
const sdt = @import("sdt.zig");
const util = @import("util");
const Gas = @import("gas.zig").Gas;
const acpi = @import("acpi.zig");
const arch = @import("../arch/arch.zig");
const mm = @import("../mm/mm.zig");

const hpet = @import("../hpet/hpet.zig");

const log = acpi.log;

pub const HpetCapabilities = packed struct(u32) {
    hardware_rev_id: u8,
    first_block_comparators: u5,
    count_size_cap_size: bool,
    _: u1 = 0,
    legacy_replacement_irq_routing: bool,
    first_block_pci_vendor_id: u16,
};

pub fn read_hpet(ptr: *align(1) const Hpet) !void {
    log.info("APIC HPET table loaded at {*}", .{ptr});
    const idx = @atomicRmw(u8, &hpet.hpet_count, .Add, 1, .monotonic);
    hpet.hpet_indices[ptr.hpet_number] = idx;
    hpet.hpet_ids[idx] = ptr.hpet_number;
    hpet.hpets[idx] = @alignCast(@ptrCast((try mm.map_io(@enumFromInt(ptr.address()), 4096, .uncached_minus)).ptr));
    hpet.caps[idx] = ptr.block_id;
    hpet.min_periodic_ticks[idx] = ptr.minimum_clock_ticks_periodic_mode;
}

pub const Hpet = extern struct {
    header: sdt.SystemDescriptorTableHeader,
    block_id: HpetCapabilities,
    base_address: Gas,
    hpet_number: u8,
    minimum_clock_ticks_periodic_mode: u16 align(1),
    page_protect: packed struct(u8) {
        page_protect: enum(u4) {
            none = 0,
            @"4k" = 1,
            @"64k" = 2,
            _,
        },
        oem_reserved: u4,
    },
};
