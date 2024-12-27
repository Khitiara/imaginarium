const arch = @import("../arch/arch.zig");
const serial = arch.serial;

const std = @import("std");

pub const msi = @import("msi.zig");
pub const pcie = @import("pcie.zig");

const IoLocation = struct {
    pub const config_address: u16 = 0xCF8;
    pub const config_data: u16 = 0xCFC;
};

pub const ConfigAddress = packed struct(u32) {
    register_offset: u8,
    function: u3,
    device: u5,
    bus: u8,
    _: u7 = 0,
    enable: bool,
};

pub const PciAddress = struct {
    segment: u16,
    function: u3,
    device: u5,
    bus: u8,
};

pub const PciBridgeAddress = struct {
    segment: u16,
    function: u3,
    device: u5,
    bus: u8,
    bridge: ?*const mcfg.PciHostBridge,
};

const mcfg = @import("../acpi/mcfg.zig");

pub fn config_read(address: PciAddress, offset: u64, comptime T: type) !T {
    const bridge = for (mcfg.host_bridges) |*b| {
        if (b.segment_group == address.segment)
            break b;
    } else null;
    return try config_read_with_bridge(.{
        .segment = address.segment,
        .bus = address.bus,
        .device = address.device,
        .function = address.function,
        .bridge = bridge,
    }, offset, T);
}

pub fn config_read_with_bridge(address: PciBridgeAddress, offset: u64, comptime T: type) !T {
    if (address.bridge) |host_bridge_map| {
        const w = offset & 0x3;
        const value = host_bridge_map.block(address.bus, address.device, address.function)[offset / 4];
        return @intCast((value >> @intCast(8 * w)) & std.math.maxInt(T));
    } else {
        if (address.segment != 0) return error.InvalidArgument;
        return config_read_legacy(.{
            .bus = address.bus,
            .device = address.device,
            .enable = true,
            .function = address.function,
            .register_offset = @intCast(offset),
        }, T);
    }
}

pub fn config_write(address: PciAddress, offset: u64, value: anytype) !void {
    const bridge = for (mcfg.host_bridges) |*b| {
        if (b.segment_group == address.segment)
            break b;
    } else null;
    try config_write_with_bridge(.{
        .segment = address.segment,
        .bus = address.bus,
        .device = address.device,
        .function = address.function,
        .bridge = bridge,
    }, offset, value);
}

pub fn config_write_with_bridge(address: PciBridgeAddress, offset: u64, value: anytype) !void {
    if (address.bridge) |host_bridge_map| {
        const w = offset & 0x3;
        const old_mask: u32 = @as(u32, std.math.maxInt(@TypeOf(value))) << @intCast(8 * w);
        const old = host_bridge_map.block(address.bus, address.device, address.function)[offset / 4] & old_mask;
        host_bridge_map.block(address.bus, address.device, address.function)[offset / 4] = @intCast(old | (value << @intCast(8 * w)));
    } else {
        if (address.segment != 0) return error.InvalidArgument;
        config_write_legacy(.{
            .bus = address.bus,
            .device = address.device,
            .enable = true,
            .function = address.function,
            .register_offset = @intCast(offset),
        }, value);
    }
}

pub fn config_read_legacy(address: ConfigAddress, comptime T: type) T {
    const w = address.register_offset & 0x3;
    var a = address;
    a.register_offset = address.register_offset & 0xFC;
    serial.out(IoLocation.config_address, a);
    const dword = serial.in(IoLocation.config_data, u32);
    return @intCast(@as(u32, @bitCast(dword >> @intCast(8 * w) & std.math.maxInt(T))));
}

pub fn config_write_legacy(address: ConfigAddress, value: anytype) void {
    const w = address.register_offset & 0x3;
    var a = address;
    a.register_offset = address.register_offset & 0xFC;
    const dword: u32 = switch (@TypeOf(value)) {
        inline i8, u8 => @as(u32, @as(u8, @bitCast(value))) << @intCast(8 * w),
        inline i16, u16 => @as(u32, @as(u16, @bitCast(value))) << @intCast(8 * w),
        inline i32, u32 => @bitCast(value),
        else => @compileError("invalid pci config register type"),
    };
    serial.out(IoLocation.config_address, a);
    serial.out(IoLocation.config_data, dword);
}
