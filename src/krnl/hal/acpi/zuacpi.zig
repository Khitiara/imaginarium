const uacpi = @import("uacpi/uacpi.zig");
const acpi = @import("acpi.zig");
const sdt = acpi.sdt;
const madt = acpi.madt;
const mcfg = acpi.mcfg;
const hpet = acpi.hpet;

const log = @import("std").log.scoped(.acpi);

comptime {
    _ = @import("uacpi/uacpi_libc.zig");
    _ = @import("uacpi/shims.zig");
}

pub fn init() !void {
    try uacpi.tables.set_table_installation_handler(&handler);
    try uacpi.initialize(.{});
    log.info("uacpi initialized", .{});
    try find_load_table(.APIC);
    log.debug("madt initialized", .{});
    try find_load_table(.MCFG);
    log.debug("mcfg initialized", .{});
    try find_load_table(.HPET);
    log.debug("hpet initialized", .{});
}

pub fn load_namespace() !void {
    const fadt = try uacpi.tables.table_fadt();
    const isa_irq = ioapic.isa_irqs[fadt.sci_int];
    try ioapic.redirect_irq(fadt.sci_int, .{
        .vector = @bitCast(@as(u8,0x20)),
        .delivery_mode = .fixed,
        .dest_mode = .physical,
        .polarity = isa_irq.polarity,
        .trigger_mode = isa_irq.trigger,
        .destination = 0,
    });

    try uacpi.namespace_load();
    try uacpi.utilities.set_interrupt_model(.ioapic);
    log.info("ACPI namespace parsed", .{});
}

const ioapic = @import("../apic/ioapic.zig");

pub fn initialize_namespace() !void {
    try uacpi.namespace_initialize();
    log.info("ACPI namespace initialized", .{});
}

fn handler(hdr: *align(1) sdt.SystemDescriptorTableHeader, _: *u64) callconv(.C) uacpi.tables.TableInstallationDisposition {
    log.debug("uacpi installed table {s}", .{&hdr.signature.to_string()});
    return .allow;
}

fn find_load_table(sig: sdt.Signature) !void {
    var tbl = (try uacpi.tables.find_table_by_signature(sig)) orelse return;
    try acpi.load_table(tbl.location.hdr);
    try uacpi.tables.table_unref(&tbl);
}