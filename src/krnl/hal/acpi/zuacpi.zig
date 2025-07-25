const zuacpi = @import("zuacpi");
const uacpi = zuacpi.uacpi;
const acpi = @import("acpi.zig");
const madt = acpi.madt;
const mcfg = acpi.mcfg;
const hpet = acpi.hpet;

const arch = @import("../hal.zig").arch;
const std = @import("std");
const log = std.log.scoped(.acpi);

comptime {
    _ = @import("shims.zig");
}

var buf: []u8 = undefined;
var early_tables_alloc: std.mem.Allocator = undefined;

pub fn early_tables(alloc: std.mem.Allocator) !void {
    buf = try alloc.alloc(u8, 8192);
    log.info("allocated early table buffer", .{});
    early_tables_alloc = alloc;
    try uacpi.setup_early_table_access(buf);
    log.info("uacpi early table access setup", .{});
    try madt.load_madt();
    log.debug("madt initialized", .{});
    try mcfg.load_mcfg();
    log.debug("mcfg initialized", .{});
}

pub fn init() !void {
    defer early_tables_alloc.free(buf);
    try uacpi.initialize(.{});
    log.info("uacpi initialized", .{});
}

pub fn load_namespace() !void {
    // const fadt = try uacpi.tables.table_fadt();
    // const isa_irq = ioapic.isa_irqs[fadt.sci_int];
    // const vector = try arch.idt.allocate_vector(.dispatch);
    // try ioapic.redirect_irq(fadt.sci_int, .{
    //     .vector = vector,
    //     .delivery_mode = .fixed,
    //     .dest_mode = .physical,
    //     .polarity = isa_irq.polarity,
    //     .trigger_mode = isa_irq.trigger,
    //     .destination = 0,
    // });

    try uacpi.namespace_load();
    try uacpi.utilities.set_interrupt_model(.ioapic);
    log.info("ACPI namespace parsed", .{});
}

const ioapic = arch.apic.ioapic;

pub fn initialize_namespace() !void {
    try uacpi.namespace_initialize();
    log.info("ACPI namespace initialized", .{});
}
