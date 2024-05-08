const std = @import("std");
const sdt = @import("sdt.zig");
const util = @import("util");
const Gas = @import("gas.zig").Gas;
const checksum = util.checksum;

pub const HpetCapabilities = packed struct(u32) {
    hardware_rev_id: u8,
    first_block_comparators: u5,
    count_size_cap_size: bool,
    _: u1 = 0,
    legacy_replacement_irq_routing: bool,
    first_block_pci_vendor_id: u16,
};

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

    pub usingnamespace checksum.add_acpi_checksum(Hpet);

    pub fn address(self: *const Hpet) usize {
        switch (self.base_address.address_space) {
            .system_memory => return self.base_address.address.system_memory,
            .system_io => return self.base_address.address.system_io,
            _ => @panic(""),
        }
    }
};

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
