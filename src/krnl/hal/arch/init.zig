const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const interrupts = @import("interrupts.zig");
const rand = @import("rand.zig");
const smp = @import("smp.zig");
const time = @import("time.zig");
const control_registers = @import("ctrl_registers.zig");

const std = @import("std");
const cmn = @import("cmn");
const types = cmn.types;
const hal = @import("../hal.zig");

const acpi = @import("../acpi/acpi.zig");

var acpi_early_table_buffer: [4096 * 2]u8 linksection(".init") = undefined;

const log = std.log.scoped(.init);
const apic = @import("../apic/apic.zig");
const zuacpi = @import("../acpi/zuacpi.zig");
const hypervisor = @import("../hypervisor.zig");
const boot_info = @import("../../boot/boot_info.zig");

pub fn platform_init() !void {
    log.info("loading bootloader-provided system info", .{});
    try boot_info.dupe_bootloader_data();
    log.info("bootloader-provided system info duplicated to managed memory", .{});
    gdt.setup_gdt();
    log.info("gdt setup and loaded", .{});
    interrupts.init();
    log.info("interrupt table initialized", .{});
    idt.load();
    log.info("interrupt table loaded", .{});
    hypervisor.init();
    log.info("checked svm information, hypervisor presence: {}", .{hypervisor.present});

    try hal.mm.mminit.init_mm();
    log.info("memory manager initialized through stage 4", .{});
    time.init_timing();
    log.info("timekeeping initialized", .{});

    idt.enable();
    log.info("interrupts enabled", .{});
    try @import("../../dispatcher/interrupts.zig").init_dispatch_interrupts();
    log.info("dispatcher interrupt handlers added", .{});
    try zuacpi.early_tables(hal.mm.pool.pool_page_allocator);
    log.info("acpi early table access setup", .{});
    apic.init();
    log.info("checked for x2apic compat and enabled apic in {s} mode", .{if (apic.x2apic.x2apic_enabled) "x2apic" else "xapic"});
    apic.bspid = apic.get_lapic_id();
    log.info("early platform init complete", .{});
}

pub fn late_init() !void {
    try zuacpi.init();
    log.info("loaded acpi sdt", .{});
    try @import("../../io/interrupts.zig").init();
    apic.ioapic.process_isa_redirections();
    try zuacpi.load_namespace();
    log.info("loaded acpi namespace", .{});
    try zuacpi.initialize_namespace();
    log.info("late platform init complete", .{});
}
