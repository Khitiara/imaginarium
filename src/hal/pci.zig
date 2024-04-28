const arch = @import("arch.zig");
const serial = arch.serial;

const IoLocation = struct {
    const config_address: u16 = 0xCF8;
    const config_data: u16 = 0xCFC;
};

pub const ConfigAddress = packed struct(u32) {
    register_offset: u8,
    function: u3,
    device: u5,
    bus: u8,
    _: u7 = 0,
    enable: bool,
};

pub fn config_read(address: ConfigAddress, comptime T: type) T {
    const w = address.register_offset & 0x3;
    var a = address;
    a.register_offset = address.register_offset & 0xFC;
    serial.out(IoLocation.config_address, a);
    const dword = serial.in(IoLocation.config_data, u32);
    switch (T) {
        inline i8, u8 => return (dword >> (8 * w)) & 0xFF,
        inline i16, u16 => return (dword >> (16 * (w / 2))) & 0xFFFF,
        inline i32, u32 => return dword,
        else => @compileError("invalid pci config register type"),
    }
}

pub fn config_write(address: ConfigAddress, value: anytype) void {
    const w = address.register_offset & 0x3;
    var a = address;
    a.register_offset = address.register_offset & 0xFC;
    const dword: u32 = switch (@TypeOf(value)) {
        inline i8, u8 => @as(u32, @bitCast(value)) << (8 * w),
        inline i16, u16 => @as(u32, @bitCast(value)) << (16 * (w / 2)),
        inline i32, u32 => @bitCast(value),
        else => @compileError("invalid pci config register type"),
    };
    serial.out(IoLocation.config_address, a);
    serial.out(IoLocation.config_data, dword);
}
