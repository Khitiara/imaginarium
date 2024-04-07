pub const acpi = @import("acpi.zig");
pub const arch = @import("arch.zig");
pub const apic = @import("apic.zig");
pub const memory = @import("memory.zig");

test {
    @import("std").testing.refAllDecls(@This());
}