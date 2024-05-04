const std = @import("std");
const assert = std.debug.assert;
const cpuid = @import("arch/x86_64/cpuid.zig");

pub usingnamespace @import("apic/interrupts.zig");

pub const RegisterId = struct {
    pub const id: u16 = 0x02;
    pub const version: u16 = 0x03;
    pub const tpr: u16 = 0x08;
    pub const apr: u16 = 0x09;
    pub const ppr: u16 = 0x0A;
    pub const eoi: u16 = 0x0B;
    pub const isr: u16 = 0x10;
    pub const tmr: u16 = 0x18;
    pub const irr: u16 = 0x20;
    pub const esr: u16 = 0x28;
    pub const icr: u16 = 0x30;
};

pub const RegisterSlice = *align(16) [0x40]extern struct { item: u32 align(16) };

pub var lapic_ptr: RegisterSlice = undefined;
pub var lapic_ids: [256]u8 = undefined;
pub var lapic_indices: [256]u8 = undefined;
pub var processor_count: u8 = 0;
pub var ioapics_buf = [_]?IOApic{null} ** @import("config").max_ioapics;
pub var ioapics_count: u8 = 0;

pub const ioapics = ioapics_count[0..ioapics_count];

pub fn get_lapic_id() u8 {
    return cpuid.cpuid(.type_fam_model_stepping_features, {}).brand_flush_count_id.apic_id;
}

pub fn get_register_ptr(reg: u16, comptime T: type) *align(16) T {
    return @ptrCast(&lapic_ptr[@intFromEnum(reg)].item);
}

pub const IOApic = struct {
    phys_addr: usize,
    gsi_base: u32,
};

test {
    _ = get_register_ptr;
}
