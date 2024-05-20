const std = @import("std");
const acpi_hpet = @import("../acpi/acpi.zig").hpet;

pub const HpetCapabilities = acpi_hpet.HpetCapabilities;

pub var hpet_count: u8 = 0;
pub var hpet_ids: [256]u8 = undefined;
pub var hpet_indices: [256]u8 = undefined;
pub var hpets = [_]?*volatile HpetRegisters{null} ** @import("config").max_hpets;
pub var caps: [hpets.len]HpetCapabilities = undefined;
pub var min_periodic_ticks: [hpets.len]u64 = undefined;

/// FOR THE LOVE OF GOD DO NOT DEREFERENCE THIS DIRECTLY
pub const HpetRegisters = extern struct {
    general_caps_and_id: packed struct(u64) {
        caps: HpetCapabilities,
        period_femptos: u32,
    },
    general_conf: packed struct(u64) {
        enable: bool,
        legacy_replacement: bool,
        _: u62 = 0,
    },
    general_interrupt_status: packed struct(u64) {
        statuses: std.bit_set.IntegerBitSet(32),
        _: u32 = 0,
    },
    main_counter_value: u64,
    // TODO the individual counters
};
