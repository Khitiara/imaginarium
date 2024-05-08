pub const acpi = @import("acpi/acpi.zig");
pub const arch = @import("arch/arch.zig");
pub const apic = @import("apic/apic.zig");
pub const memory = @import("memory.zig");

test {
    @import("std").testing.refAllDecls(@This());
}