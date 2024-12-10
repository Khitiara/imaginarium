const std = @import("std");
const sdt = @import("sdt.zig");
const util = @import("util");
const arch = @import("../arch/arch.zig");
const assert = std.debug.assert;
const checksum = util.checksum;

pub const Mcfg = extern struct {
    header: sdt.SystemDescriptorTableHeader,
    _: [8]u8 align(1) = [_]u8{0} ** 8,

    pub usingnamespace checksum.add_acpi_checksum(Mcfg);

    pub fn bridges(self: *align(1) const Mcfg) []align(1) const PciHostBridge {
        return std.mem.bytesAsSlice(PciHostBridge, @as([*]const u8, @ptrCast(self))[@sizeOf(Mcfg)..self.header.length]);
    }
};

pub var host_bridges: []const PciHostBridge = undefined;

pub const PciHostBridge = extern struct {
    base: u64,
    segment_group: u16,
    bus_start: u8,
    bus_end: u8,
    _: u32 = 0,

    const AddrBreakdown = packed struct(u64) {
        _1: u12 = 0,
        function: u3,
        device: u5,
        bus: u8,
        _2: u36 = 0,
    };
    pub fn block(self: *const PciHostBridge, bus: u8, device: u5, function: u3) *align(4096) volatile [4096 / 32]u32 {
        assert(bus >= self.bus_start);
        assert(bus <= self.bus_end);
        var breakdown: AddrBreakdown = @bitCast(self.base);
        breakdown.bus = bus;
        breakdown.device = device;
        breakdown.function = function;
        return arch.ptr_from_physaddr(*align(4096) volatile [4096 / 32]u32, @enumFromInt(@as(u64,@bitCast(breakdown))));
    }
};

const log = @import("acpi.zig").log;

pub fn set_table(table: *align(1) const Mcfg) !void {
    log.info("PCI(E) MCFG table loaded at {*}", .{table});
    const b = table.bridges();
    const b2 = try arch.vmm.gpa.allocator().alloc(PciHostBridge, b.len);
    @memcpy(b2, b);
    host_bridges = b2;
    for (host_bridges, 0..) |host_bridge, i| {
        log.debug("Host Bridge {d}: SegGrp 0x{X:0>4} buses {X:0>2}-{X:0>2} mapped with base 0x{X:0>16}", .{ i, host_bridge.segment_group, host_bridge.bus_start, host_bridge.bus_end, host_bridge.base });
    }
}
