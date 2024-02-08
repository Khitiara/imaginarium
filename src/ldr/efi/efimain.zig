const std = @import("std");
const uefi = std.os.uefi;
const hal = @import("hal");

const apic = hal.apic;
const acpi = hal.acpi;
const meta = std.meta;
const debug = std.debug;
const rdsp = acpi.rdsp;
const sdt = acpi.sdt;

const lstr = std.unicode.utf8ToUtf16LeStringLiteral;

const known_system_config_table = enum {
    acpi_20,
    acpi_10,
};

var tables = std.EnumMap(known_system_config_table, *anyopaque){};

fn load_config_tables() void {
    const tables_slice = uefi.system_table.configuration_table[0..uefi.system_table.number_of_table_entries];
    for (tables_slice) |table| {
        inline for (comptime meta.tags(known_system_config_table)) |t| {
            if (uefi.Guid.eql(table.vendor_guid, @field(uefi.tables.ConfigurationTable, @tagName(t) ++ "_table_guid"))) {
                tables.put(t, table.vendor_table);
            }
        }
    }
}

pub fn inner() !void {
    const boot_services = uefi.system_table.boot_services.?;
    load_config_tables();
    const acpi_tbl = tables.get(.acpi_20) orelse tables.get(.acpi_10) orelse return error.acpi_table_not_found;
    const rdsp_ptr = try rdsp.Rdsp.fetch_from_pointer(acpi_tbl);
    const info = rdsp.RdspInfo.from_rdsp(rdsp_ptr);
    try acpi.load_sdt(info.table_addr);
    _ = boot_services;
}

pub fn main() void {
    inner() catch |e| {
        const status: uefi.Status = switch (e) {
            error.unrecognized_version => .IncompatibleVersion,
            error.invalid_global_table_alignment => .Aborted,
            error.invalid_global_table_signature => .Aborted,
            error.acpi_table_not_found => .Aborted,
        };
        if (uefi.system_table.boot_services) |bs| {
            _ = bs.exit(uefi.handle, status, 0, null);
        }
        std.os.abort();
    };
}

const std_options = struct {
    usingnamespace @import("efilog");
};
