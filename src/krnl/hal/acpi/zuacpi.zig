const uacpi = @import("uacpi/uacpi.zig");
const acpi = @import("acpi.zig");
const sdt = acpi.sdt;
const madt = acpi.madt;
const mcfg = acpi.mcfg;
const hpet = acpi.hpet;

const arch = @import("../arch/arch.zig");
const std = @import("std");
const log = std.log.scoped(.acpi);

comptime {
    _ = @import("uacpi/uacpi_libc.zig");
    _ = @import("uacpi/shims.zig");
}

var buf: []u8 = undefined;
var early_tables_alloc: std.mem.Allocator = undefined;

pub fn early_tables(alloc: std.mem.Allocator) !void {
    buf = try alloc.alloc(u8, 8192);
    log.info("allocated early table buffer", .{});
    early_tables_alloc = alloc;
    try uacpi.setup_early_table_access(buf);
    log.info("uacpi early table access setup", .{});
    try find_load_table(.APIC);
    log.debug("madt initialized", .{});
    try find_load_table(.MCFG);
    log.debug("mcfg initialized", .{});
}

pub fn init() !void {
    defer early_tables_alloc.free(buf);
    try uacpi.initialize(.{});
    log.info("uacpi initialized", .{});
}

pub fn load_namespace() !void {
    const fadt = try uacpi.tables.table_fadt();
    const isa_irq = ioapic.isa_irqs[fadt.sci_int];
    const vector = try arch.idt.allocate_vector(.dispatch);
    try ioapic.redirect_irq(fadt.sci_int, .{
        .vector = vector,
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

pub fn find_load_table(sig: sdt.Signature) !void {
    var tbl = (try uacpi.tables.find_table_by_signature(sig)) orelse return;
    try acpi.load_table(tbl.location.hdr);
    try uacpi.tables.table_unref(&tbl);
}
