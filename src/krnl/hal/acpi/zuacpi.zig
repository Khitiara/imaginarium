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
    try uacpi.namespace_load();
    log.info("ACPI namespace parsed", .{});
}

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