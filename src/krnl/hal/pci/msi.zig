const arch = @import("../hal.zig").arch;

pub const MessageAddressRegister = arch.acpi_types.MsiAddressRegister;
pub const MessageDataRegister = arch.acpi_types.MsiDataRegister;
