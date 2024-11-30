const uacpi = @import("uacpi/uacpi.zig");
const acpi = @import("acpi.zig");
const sdt = acpi.sdt;
const madt = acpi.madt;
const mcfg = acpi.mcfg;
const hpet = acpi.hpet;

comptime {
    _ = @import("uacpi/uacpi_libc.zig");
    _ = @import("uacpi/shims.zig");
}

pub fn init() !void {
    try uacpi.initialize(.{});
    try find_load_table(.APIC);
    try find_load_table(.MCFG);
    try find_load_table(.HPET);
}

fn find_load_table(sig: sdt.Signature) !void {
    var tbl = try uacpi.tables.find_table_by_signature(sig) orelse return;
    try acpi.load_table(tbl.location.hdr);
    try uacpi.tables.table_unref(&tbl);
}