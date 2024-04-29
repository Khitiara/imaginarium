const sdt = @import("sdt.zig");
const util = @import("util");
const checksum = util.checksum;
const WindowStructIndexer = util.WindowStructIndexer;

const apic = @import("../apic.zig");
const log = @import("../acpi.zig").log;

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
            flags: packed struct(u8) {
                polarity: enum(u2) {
                    default,
                    active_high,
                    reserved,
                    active_low,
                },
                trigger: enum(u2) {
                    default,
                    edge_triggered,
                    reserved,
                    level_triggered,
                },
                _: u12 = 0,
            },
        },
        else => void,
    };
}

pub fn read_madt(ptr: *const Madt) void {
    log.info("APIC MADT table loaded at {*}", .{ptr});
    var lapic_ptr: usize = ptr.lapic_addr;
    const entries_base_ptr = @as([*]const u8, @ptrCast(ptr))[@sizeOf(Madt)..ptr.header.length];
    var indexer = WindowStructIndexer(MadtEntryHeader){ .buf = entries_base_ptr };
    while (indexer.offset < entries_base_ptr.len) {
        const hdr = indexer.current();

        switch (hdr.type) {
            .io_apic => {
                const payload = @as(*const MadtEntryPayload(.io_apic), @alignCast(@ptrCast(hdr)));
                assert(hdr.length == 12);

                apic.ioapics_buf[apic.ioapics_count] = .{ .phys_addr = payload.ioapic_addr, .gsi_base = payload.gsi_base };
                apic.ioapics_count += 1;
            },
            .local_apic_addr_override => {
                const payload = @as(*const MadtEntryPayload(.local_apic_addr_override), @alignCast(@ptrCast(hdr)));
                assert(hdr.length == 12);

                lapic_ptr = payload.lapic_addr;
            },

            else => {},
        }

        indexer.advance(hdr.length);
    }
    apic.lapic_ptr = @ptrFromInt(lapic_ptr);
}

test {
    _ = Madt;
    _ = MadtEntryPayload;
    _ = read_madt;
}
