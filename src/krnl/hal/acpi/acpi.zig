pub const madt = @import("madt.zig");
pub const mcfg = @import("mcfg.zig");
pub const hpet = @import("hpet.zig");
const std = @import("std");

pub const log = std.log.scoped(.acpi);
