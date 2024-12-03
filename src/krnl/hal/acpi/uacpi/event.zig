const uacpi = @import("uacpi.zig");
const acpi = @import("../../acpi/acpi.zig");

extern fn uacpi_finalize_gpe_initialization() uacpi.uacpi_status;
pub fn finalize_gpe_initialization() uacpi.Error!void {
    return uacpi_finalize_gpe_initialization().err();
}
