const std = @import("std");
const util = @import("util");
const acpi = @import("acpi.zig");
const arch = @import("../arch/arch.zig");
const mm = @import("../mm/mm.zig");

const hpet = @import("../hpet/hpet.zig");

const log = acpi.log;

const zuacpi = @import("zuacpi");
const Gas = zuacpi.Gas;
const find_table_by_signature = zuacpi.uacpi.tables.find_table_by_signature;
const tbl_hpet = zuacpi.hpet;

pub fn read_hpet(ptr: *align(1) const tbl_hpet.Hpet) !void {
    log.info("APIC HPET table loaded at {*}", .{ptr});
    const idx = @atomicRmw(u8, &hpet.hpet_count, .Add, 1, .monotonic);
    hpet.hpet_indices[ptr.hpet_number] = idx;
    hpet.hpet_ids[idx] = ptr.hpet_number;
    hpet.hpets[idx] = ptr.base_address;
    hpet.caps[idx] = ptr.block_id;
    hpet.min_periodic_ticks[idx] = ptr.minimum_clock_ticks_periodic_mode;
}
