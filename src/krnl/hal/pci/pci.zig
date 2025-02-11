const arch = @import("../arch/arch.zig");
const serial = arch.serial;

const std = @import("std");

pub const msi = @import("msi.zig");

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
        const block = host_bridge_map.block(address.bus, address.device, address.function);

        // https://github.com/ziglang/zig/issues/10367
        const value = asm volatile (
            \\ movl (%[block], %[offset], 4), %[out]
            : [out] "={eax}" (-> u32),
            : [block] "r" (block),
              [offset] "r" (offset / 4),
            : "memory"
        );

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
        const old_mask: u32 = ~(@as(u32, std.math.maxInt(@TypeOf(value))) << @intCast(8 * w));
        const shifted: u32 = @intCast(value << @intCast(8 * w));
        const block = host_bridge_map.block(address.bus, address.device, address.function);

        // https://github.com/ziglang/zig/issues/10367
        asm volatile (
            \\ movl (%[base], %[offset], 4), %%eax
            \\ andl %[mask], %%eax
            \\ orl %[shifted], %%eax
            \\ movl %%eax, (%[base], %[offset], 4)
            :
            : [base] "r" (block),
              [offset] "r" (offset / 4),
              [mask] "ir" (old_mask),
              [shifted] "ir" (shifted),
            : "eax", "memory"
        );
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
    // in theory the data should be a DWORD access from port 0xCFC followed by some bit
    // math but linux does a target-type-sized access to port (0xCFC + (offset % 3)) and
    // if it works for them then its not my fault if it breaks later
    return asm volatile (
        \\ movw $0xCF8, %%dx
        \\ outl %[addr], %%dx
        \\ movw %[dataport], %%dx
        \\ in %%dx, %[result]
        : [result] "={al},={ax},={eax}" (-> T),
        : [addr] "{al},{ax},{eax}" (a),
          [dataport] "r" (@as(u16, 0xCFC) + w),
        : "memory", "dx"
    );
}

pub fn config_write_legacy(address: ConfigAddress, value: anytype) void {
    const w = address.register_offset & 0x3;
    var a = address;
    a.register_offset = address.register_offset & 0xFC;

    // in theory this should be a DWORD read from port 0xCFC followed by some bit math
    // and another write to the same port 0xCFC, but linux does a target-type-sized
    // access to port (0xCFC + (offset % 3)) and if it works for them then its not my
    // fault if it breaks later
    asm volatile (
        \\ movw $0xCF8, %%dx
        \\ outl %[addr], %%dx
        \\ movw %[dataport], %%dx
        \\ out %[value], %%dx
        :
        : [addr] "{al},{ax},{eax}" (a),
          [value] "{al},{ax},{eax}" (value),
          [dataport] "N{dx}" (@as(u16, 0xCFC) + w),
    : "memory", "dx"
    );
}
