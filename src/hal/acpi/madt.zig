const sdt = @import("sdt.zig");
const util = @import("util");
const checksum = util.checksum;
const WindowStructIndexer = util.WindowStructIndexer;

const apic = @import("../apic/apic.zig");
const log = @import("acpi.zig").log;

const assert = @import("std").debug.assert;

pub const MadtFlags = packed struct(u32) {
    pcat_compat: bool,
    _: u31,
};

pub const Madt = extern struct {
    header: sdt.SystemDescriptorTableHeader,
    lapic_addr: u32,
    flags: MadtFlags,

    pub usingnamespace checksum.add_acpi_checksum(Madt);
};

const MadtEntryType = enum(u8) {
    local_apic = 0,
    io_apic,
    interrupt_source_override,
    nmi_source,
    local_nmi,
    local_apic_addr_override,
    io_sapic,
    local_sapic,
    platform_interrupt_sources,
    proc_local_x2apic,
    local_x2apic_nmi,
    gic_cpu_interface,
    gic_msi_frame,
    gic_redistributor,
    gic_interrupt_translation_service,
    multiprocessor_wakeup,
    _,
};

const MadtEntryHeader = extern struct {
    type: MadtEntryType,
    length: u8,
};

pub const MadtInterruptSourceFlags = packed struct(u16) {
    polarity: apic.AcpiPolarity,
    trigger: apic.AcpiTrigger,
    _: u12 = 0,
};

fn MadtEntryPayload(comptime t: MadtEntryType) type {
    return switch (t) {
        .local_apic => extern struct {
            header: MadtEntryHeader,
            processor_uid: u8,
            local_apic_id: u8,
            flags: packed struct(u32) {
                enabled: bool,
                online_capable: bool,
                _: u30,
            },
        },
        .local_nmi => extern struct {
            header: MadtEntryHeader align(4),
            processor_uid: u8,
            flags: MadtInterruptSourceFlags align(1),
            pin: u8,
        },
        .local_apic_addr_override => extern struct {
            header: MadtEntryHeader align(4),
            lapic_addr: u64 align(4),
        },
        .io_apic => extern struct {
            header: MadtEntryHeader,
            ioapic_id: u8,
            ioapic_addr: u32 align(4),
            gsi_base: u32 align(4),
        },
        .interrupt_source_override => extern struct {
            header: MadtEntryHeader,
            bus: u8,
            source: u8,
            gsi: u32,
            flags: MadtInterruptSourceFlags align(1),
        },
        else => void,
    };
}

pub fn read_madt(ptr: *align(1) const Madt) void {
    var lapic_uids: [255]u8 = undefined;
    var uid_nmi_pins: [255]apic.LapicNmiPin = undefined;
    log.info("APIC MADT table loaded at {*}", .{ptr});
    @memset(&apic.lapic_nmi_pins, .{
        .pin = .none,
        .polarity = .default,
        .trigger = .default,
    });
    var lapic_ptr: usize = ptr.lapic_addr;
    const entries_base_ptr = @as([*]const u8, @ptrCast(ptr))[@sizeOf(Madt)..ptr.header.length];
    var indexer = WindowStructIndexer(MadtEntryHeader){ .buf = entries_base_ptr };
    while (indexer.offset < entries_base_ptr.len) {
        const hdr = indexer.current();

        switch (hdr.type) {
            .local_apic => {
                const payload = @as(*align(1) const MadtEntryPayload(.local_apic), @ptrCast(hdr));
                assert(hdr.length == 8);
                const idx = @atomicRmw(u8, &apic.processor_count, .Add, 1, .monotonic);
                lapic_uids[idx] = payload.processor_uid;
                apic.lapic_ids[idx] = payload.local_apic_id;
                apic.lapic_indices[payload.local_apic_id] = idx;
                apic.lapic_enabled[payload.local_apic_id] = payload.flags.enabled;
                apic.lapic_online_capable[payload.local_apic_id] = payload.flags.online_capable;
            },
            .io_apic => {
                const payload = @as(*align(1) const MadtEntryPayload(.io_apic), @ptrCast(hdr));
                assert(hdr.length == 12);

                apic.ioapics_buf[@atomicRmw(u8, &apic.ioapics_count, .Add, 1, .monotonic)] = .{
                    .id = payload.ioapic_id,
                    .phys_addr = payload.ioapic_addr,
                    .gsi_base = payload.gsi_base,
                };
            },
            .local_apic_addr_override => {
                const payload = @as(*align(1) const MadtEntryPayload(.local_apic_addr_override), @ptrCast(hdr));
                assert(hdr.length == 12);

                lapic_ptr = payload.lapic_addr;
            },
            .local_nmi => {
                const payload = @as(*align(1) const MadtEntryPayload(.local_nmi), @ptrCast(hdr));
                assert(hdr.length == 6);
                const info: apic.LapicNmiPin = .{
                    .pin = switch (payload.pin) {
                        0 => .lint0,
                        1 => .lint1,
                        else => .none,
                    },
                    .trigger = payload.flags.trigger,
                    .polarity = payload.flags.polarity,
                };
                if (payload.processor_uid == 0xFF) {
                    @memset(&uid_nmi_pins, info);
                } else {
                    uid_nmi_pins[payload.processor_uid] = info;
                }
            },
            else => {
                log.debug("Found MADT payload {x}", .{hdr.type});
            },
        }

        indexer.advance(hdr.length);
    }
    for (lapic_uids[0..apic.processor_count], apic.lapic_ids[0..apic.processor_count]) |uid, id| {
        apic.lapic_nmi_pins[id] = uid_nmi_pins[uid];
    }
    apic.lapic_ptr = @import("../arch/arch.zig").ptr_from_physaddr(apic.RegisterSlice, lapic_ptr);
}

test {
    _ = Madt;
    _ = MadtEntryPayload;
    _ = read_madt;
}
