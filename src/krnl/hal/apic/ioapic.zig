pub var ioapics_buf: [@import("config").max_ioapics]IOApic = undefined;
pub var ioapics_count: u8 = 0;

const apic = @import("apic.zig");
const std = @import("std");
const log = std.log.scoped(.ioapic);
const hal = @import("../hal.zig");

fn read_ioapic(base: [*]volatile u32, reg: u32) u32 {
    base[0] = reg;
    return base[4];
}

fn write_ioapic(base: [*]volatile u32, reg: u32, value: u32) void {
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
    base_addr: [*]u32,
    gsi_base: u32,
};

pub const IsaIrq = struct {
    gsi: u32,
    polarity: apic.Polarity,
    trigger: apic.TriggerMode,
    ioapic_idx: u8 = 0,
    ioapic_ofs: u32 = 0,
    cpu_irq: u8 = 0,
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

pub const IoRedTblEntry = packed struct(u64) {
    vector: hal.InterruptVector,
    delivery_mode: apic.DeliveryMode,
    dest_mode: apic.DestinationMode,
    pending: bool = false,
    polarity: apic.Polarity,
    remote_irr: bool = false,
    trigger_mode: apic.TriggerMode,
    masked: bool = false,
    _: u39 = 0,
    destination: u8,
};

fn ioapic_by_gsi_comp(_: void, lhs: IOApic, rhs: IOApic) bool {
    return lhs.gsi_base < rhs.gsi_base;
}

// var gsi_map: std.AutoArrayHashMap(u32, u8) = undefined;

const QueuedSpinLock = @import("../QueuedSpinLock.zig");
const smp = @import("../../smp.zig");
var ioapic_lock: QueuedSpinLock = .{};

pub fn redirect_irq(gsi: u32, redirection: IoRedTblEntry) !void {
    var token: QueuedSpinLock.Token = undefined;
    if (smp.smp_initialized) ioapic_lock.lock(&token);
    defer if (smp.smp_initialized) token.unlock();
    var base: [*]volatile u32 = undefined;
    var entry: u32 = undefined;
    if (gsi < 32) {
        const isa_irq = &isa_irqs[gsi];
        if (isa_irq.cpu_irq != 0) return error.AlreadyMappedIsaIrq;
        isa_irq.cpu_irq = @bitCast(redirection.vector);
        const ioapic = ioapics_buf[isa_irq.ioapic_idx];
        base = ioapic.base_addr;
        entry = 0x10 + isa_irq.ioapic_ofs * 2;
    } else {
        for (ioapics_buf[0..ioapics_count]) |ioapic| {
            if (gsi < ioapic.gsi_base)
                return error.NoSuitableIoApic;
            const top: IoApicVersion = @bitCast(read_ioapic(ioapic.base_addr, 1));
            if (ioapic.gsi_base + top.max_entries < gsi)
                continue;

            base = ioapic.base_addr;
            entry = gsi - ioapic.gsi_base;
            break;
        }
    }
    const halves: [2]u32 = @bitCast(redirection);
    write_ioapic(base, entry + 1, halves[1]);
    write_ioapic(base, entry, halves[0]);
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
            const top: IoApicVersion = @bitCast(read_ioapic(ioapic.base_addr, 1));
            if (ioapic.gsi_base + top.max_entries < irq.gsi)
                continue;

            base = ioapic.gsi_base;
            idx = @intCast(i);
            break;
        }
        // log.debug("redirecting IRQ#{X:0>2} to IOAPIC index {d}, id 0x{x}, offset {d} from gsi base {d}", .{j, idx, ioapics[idx].id, irq.gsi - base, base});
        irq.ioapic_idx = idx;
        irq.ioapic_ofs = irq.gsi - base;
    }
}
