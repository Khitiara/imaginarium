const std = @import("std");
const sdt = @import("sdt.zig");
const util = @import("util");
const hal = @import("../hal.zig");
const arch = hal.arch;
const mm = hal.mm;
const assert = std.debug.assert;

pub const Mcfg = extern struct {
    header: sdt.SystemDescriptorTableHeader,
    _: [8]u8 align(1) = [_]u8{0} ** 8,

    pub fn bridges(self: *align(1) const Mcfg) []align(1) const RawPciHostBridge {
        return std.mem.bytesAsSlice(RawPciHostBridge, @as([*]const u8, @ptrCast(self))[@sizeOf(Mcfg)..self.header.length]);
    }
};

pub var host_bridges: []const PciHostBridge = undefined;

const RawPciHostBridge = extern struct {
    base: u64,
    segment_group: u16,
    bus_start: u8,
    bus_end: u8,
    _: u32 = 0,
};

var bridge_map_lock: hal.SpinLock = .{};

pub const PciHostBridge = struct {
    base: u64,
    ptr: ?[]align(4096) [32][8][4096 / 4]u32 = null,
    segment_group: u16,
    bus_start: u8,
    bus_end: u8,

    const AddrBreakdown = packed struct(u64) {
        _1: u20 = 0,
        bus: u8,
        _2: u36 = 0,
    };

    pub noinline fn map(self: *PciHostBridge) !void {
        if (self.ptr != null) return;

        const iflg = bridge_map_lock.lock_cli();
        defer bridge_map_lock.unlock_sti(iflg);

        if (self.ptr != null) return;

        var bdown: AddrBreakdown = @bitCast(self.base);
        bdown.bus = self.bus_start;


        const len: usize = (@as(usize, self.bus_end - self.bus_start) + 1) * comptime (std.heap.pageSize() * 32 * 8);
        const b = try mm.map_io(@enumFromInt(@as(u64, @bitCast(bdown))), len, .uncached_minus);

        // log.debug("bridge {d}-{d} mapped to address {*} with length {x}", .{ self.bus_start, self.bus_end, b.ptr, len });

        self.ptr = @alignCast(std.mem.bytesAsSlice([32][8][4096 / 4]u32, b));
    }

    pub fn block(self: *const PciHostBridge, bus: u8, device: u5, function: u3) *align(4096) [4096 / 4]u32 {
        assert(bus >= self.bus_start);
        assert(bus <= self.bus_end);

        return @alignCast(&(self.ptr orelse unreachable)[bus - self.bus_start][device][function]);
    }
};

const log = @import("acpi.zig").log;

pub noinline fn set_table(table: *align(1) const Mcfg) !void {
    log.info("PCI(E) MCFG table loaded at {*}", .{table});
    const b = table.bridges();
    const b2 = try mm.pool.pool_allocator.alloc(PciHostBridge, b.len);
    for (b, b2) |*br, *bm| {
        bm.* = .{
            .base = br.base,
            .bus_start = br.bus_start,
            .bus_end = br.bus_end,
            .segment_group = br.segment_group,
        };
        try bm.map();
    }
    host_bridges = b2;
    for (host_bridges, 0..) |host_bridge, i| {
        log.debug("Host Bridge {d}: SegGrp 0x{X:0>4} buses {X:0>2}-{X:0>2} mapped with base 0x{X:0>16}", .{ i, host_bridge.segment_group, host_bridge.bus_start, host_bridge.bus_end, host_bridge.base });
    }
}
