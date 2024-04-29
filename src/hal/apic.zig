const std = @import("std");
const assert = std.debug.assert;

pub const RegisterId = enum(u16) {
    id = 0x2,
    version = 0x3,
    tpr = 0x8,
    apr = 0x9,
    ppr = 0xA,
    eoi = 0xB,
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

// is this even necessary? idk commenting it out
// pub fn readLargeRegister(RegEntry: type, reg: RegisterId) RegEntry {
//     const int = @typeInfo(RegEntry).Int;
//     assert(int.signedness == .unsigned);
//     const bits = int.bits;
//     const entries = (comptime std.math.divExact(u16, bits, 32)) catch @compileError("Invalid registry entry type");
//     const buf: [entries]u32 = [_]u32{0} ** entries;
//     for (0..entries) |i| {
//         buf[entries - i - 1] = @byteSwap(lapic_ptr[@intFromEnum(reg) + i].item);
//     }
//     return std.mem.readInt(RegEntry, @ptrCast(&buf), .big);
// }

pub const IOApic = struct {
    phys_addr: usize,
    gsi_base: u32,
};

test {
    _ = getRegisterPtr;
    // _ = readLargeRegister;
}
