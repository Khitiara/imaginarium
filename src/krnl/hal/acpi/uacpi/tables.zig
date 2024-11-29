const uacpi = @import("uacpi2.zig");
const acpi = @import("../../hal/acpi/acpi.zig");
const sdt = acpi.sdt;

const acpi_sdt_hdr = sdt.SystemDescriptorTableHeader;

pub const uacpi_table = extern struct {
    location: extern union {
        virt_addr: u64,
        ptr: ?*anyopaque,
        hdr: ?*const sdt.SystemDescriptorTableHeader,
    },
    index: usize,
};

pub const table_installation_disposition = enum(u32) {
    allow = 0,
    deny,
    virtual_override,
    physical_override,
};

pub const table_installation_handler = *const fn (hdr: *acpi_sdt_hdr, out_override_address: *u64) table_installation_disposition;
extern fn uacpi_set_table_installation_handler(handler: table_installation_handler) uacpi.uacpi_status;

pub fn set_table_installation_handler(handler: table_installation_handler) !void {
    return uacpi_set_table_installation_handler(handler).err();
}
