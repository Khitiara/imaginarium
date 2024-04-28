const std = @import("std");
const sdt = @import("sdt.zig");
const util = @import("util");
const checksum = util.checksum;

pub const Mcfg = extern struct {
    header: sdt.SystemDescriptorTableHeader,
    _: [8]u8 align(1) = [_]u8{0} ** 8,

    pub usingnamespace checksum.add_acpi_checksum(Mcfg);

    pub fn bridges(self: *const Mcfg) []const PciHostBridge {
        return std.mem.bytesAsSlice(PciHostBridge, @as([]align(@alignOf(PciHostBridge)) const u8, @alignCast(std.mem.asBytes(self)[@sizeOf(Mcfg)..self.header.length])));
    }
};

pub var host_bridges: []const PciHostBridge = undefined;

pub const PciHostBridge = extern struct {
    base: usize,
    segment_group: u16,
    bus_start: u8,
    bus_end: u8,
    _: u32 = 0,
};
