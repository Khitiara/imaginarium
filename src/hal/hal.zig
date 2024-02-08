pub const acpi = @import("acpi.zig");
pub const arch = @import("arch.zig");
pub const apic = @import("apic.zig");

test {
    @import("std").testing.refAllDecls(@This());
}