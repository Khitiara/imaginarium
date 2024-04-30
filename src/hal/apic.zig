const std = @import("std");
const assert = std.debug.assert;

pub const RegisterId = enum(u16) {
    id = 0x02,
    version = 0x03,
    tpr = 0x08,
    apr = 0x09,
    ppr = 0x0A,
    eoi = 0x0B,
    isr = 0x10,
    tmr = 0x18,
    irr = 0x20,
    esr = 0x28,
    icr = 0x30,
    _,
};

pub const RegisterSlice = *align(16) [0x40]extern struct { item: u32 align(16) };

pub var lapic_ptr: RegisterSlice = undefined;
pub var ioapics_buf = [_]?IOApic{null} ** @import("config").max_ioapics;
pub var ioapics_count: u8 = 0;

pub const ioapics = ioapics_count[0..ioapics_count];

pub fn getRegisterPtr(reg: RegisterId) *align(16) u32 {
    return &lapic_ptr[@intFromEnum(reg)].item;
}

pub const IOApic = struct {
    phys_addr: usize,
    gsi_base: u32,
};

test {
    _ = getRegisterPtr;
    // _ = readLargeRegister;
}
