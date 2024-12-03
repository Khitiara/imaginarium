pub var ioapics_buf: [@import("config").max_ioapics]IOApic = undefined;
pub var ioapics_count: u8 = 0;

const apic = @import("apic.zig");
const std = @import("std");
const log = std.log.scoped(.ioapic);

fn read_ioapic(base: [*]volatile u32, reg: u8) u32 {
    base[0] = reg;
    return base[4];
}

fn write_ioapic(base: [*]volatile u32, reg: u8, value: u32) void {
    base[0] = reg;
    base[4] = value;
}

const IoApicVersion = packed struct(u32) {
    version: u8,
    _1: u8 = 0,
    max_entries: u8,
    _2: u8 = 0,
};

pub const IOApic = struct {
    id: u8,
    phys_addr: [*]volatile u32,
    gsi_base: u32,
};

pub const IsaIrq = struct {
    gsi: u32,
    polarity: apic.Polarity,
    trigger: apic.TriggerMode,
    ioapic_idx: u8 = 0,
    ioapic_ofs: u32 = 0,
};

pub var isa_irqs: [32]IsaIrq = blk: {
    var scratch: [32]IsaIrq = undefined;
    for (0..32) |i| {
        scratch[i] = .{
            .gsi = i,
            .polarity = .active_high,
            .trigger = .edge,
        };
    }
    const s = scratch;
    break :blk s;
};

fn ioapic_by_gsi_comp(_: void, lhs: IOApic, rhs: IOApic) bool {
    return lhs.gsi_base < rhs.gsi_base;
}

pub fn process_isa_redirections() void {
    std.sort.block(IOApic, ioapics_buf[0..ioapics_count], {}, ioapic_by_gsi_comp);
    log.info("NOTE: sorted ioapics buffer by GSI base", .{});

    const ioapics = ioapics_buf[0..ioapics_count];
    for (&isa_irqs) |*irq| {
        var idx: u8 = 0;
        var base: u32 = 0;
        for (ioapics, 0..) |ioapic, i| {
            if (irq.gsi < ioapic.gsi_base)
                continue;
            const top: IoApicVersion = @bitCast(read_ioapic(ioapic.phys_addr, 1));
            if (ioapic.gsi_base + top.max_entries < irq.gsi)
                continue;
            if (ioapic.gsi_base > base) {
                base = ioapic.gsi_base;
                idx = @intCast(i);
            }
        }
        // log.debug("redirecting IRQ#{X:0>2} to IOAPIC index {d}, id 0x{x}, offset {d} from gsi base {d}", .{j, idx, ioapics[idx].id, irq.gsi - base, base});
        irq.ioapic_idx = idx;
        irq.ioapic_ofs = irq.gsi - base;
    }
}