const std = @import("std");
const sdt = @import("sdt.zig");
const util = @import("util");
const checksum = util.checksum;

pub const Mcfg = extern struct {
    header: sdt.SystemDescriptorTableHeader,
    _: [8]u8 align(1) = [_]u8{0} ** 8,

    pub usingnamespace checksum.add_acpi_checksum(Mcfg);

    pub fn bridges(self: *align(1) const Mcfg) []align(1) const PciHostBridge {
        return std.mem.bytesAsSlice(PciHostBridge, @as([*]const u8, @ptrCast(self))[@sizeOf(Mcfg)..self.header.length]);
    }
};

pub var host_bridges: []align(1) const PciHostBridge = undefined;

pub const PciHostBridge = extern struct {
    base: usize,
    segment_group: u16,
    bus_start: u8,
    bus_end: u8,
    _: u32 = 0,
};

const log = @import("acpi.zig").log;

pub fn set_table(table: *align(1) const Mcfg) void {
    log.info("PCI(E) MCFG table loaded at {*}", .{table});
    host_bridges = table.bridges();
}
