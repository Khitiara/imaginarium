const uacpi = @import("uacpi.zig");
const acpi = @import("../../acpi/acpi.zig");
const sdt = acpi.sdt;

pub const uacpi_table = extern struct {
    location: extern union {
        virt_addr: u64,
        ptr: *align(1) anyopaque,
        hdr: *align(1) const sdt.SystemDescriptorTableHeader,
    },
    index: usize,
};

pub const TableInstallationDisposition = enum(u32) {
    allow = 0,
    deny,
    virtual_override,
    physical_override,
};

pub const TableInstallationHandler = *const fn (hdr: *align(1) sdt.SystemDescriptorTableHeader, out_override_address: *u64) callconv(.C) TableInstallationDisposition;
extern fn uacpi_set_table_installation_handler(handler: TableInstallationHandler) uacpi.uacpi_status;

pub fn set_table_installation_handler(handler: TableInstallationHandler) !void {
    return uacpi_set_table_installation_handler(handler).err();
}

extern fn uacpi_table_find_by_signature(signature: *const [4]u8, out_table: *uacpi_table) uacpi.uacpi_status;
pub fn find_table_by_signature(signature: sdt.Signature) !?uacpi_table {
    var t: uacpi_table = undefined;
    uacpi_table_find_by_signature(&signature.to_string(), &t).err() catch |err| switch (err) {
        // error.NotFound => return null,
        else => return err,
    };
    return t;
}

extern fn uacpi_table_ref(*uacpi_table) uacpi.uacpi_status;
extern fn uacpi_table_unref(*uacpi_table) uacpi.uacpi_status;

pub fn table_unref(tbl: *uacpi_table) !void {
    return uacpi_table_unref(tbl).err();
}

pub fn table_ref(tbl: *uacpi_table) !void {
    return uacpi_table_ref(tbl).err();
}
