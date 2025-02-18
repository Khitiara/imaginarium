pub const sdt = @import("sdt.zig");
// pub const rsdp = @import("rsdp.zig");
pub const madt = @import("madt.zig");
pub const mcfg = @import("mcfg.zig");
pub const hpet = @import("hpet.zig");
pub const fadt = @import("fadt.zig");
const std = @import("std");
const zuid = @import("zuid");

pub const GlobalSdtLoadError = error{
    invalid_global_table_signature,
    unexpected_global_table_signature,
    invalid_global_table_alignment,
    Overflow,
};

pub const GlobalSdtError = GlobalSdtLoadError ;

pub const log = std.log.scoped(.acpi);

pub fn load_table(t: *align(1) const sdt.SystemDescriptorTableHeader) !void {
    switch (t.signature) {
        .APIC => try madt.read_madt(@ptrCast(t)),
        .MCFG => try mcfg.set_table(@ptrCast(t)),
        .HPET => try hpet.read_hpet(@ptrCast(t)),
        else => |s| {
            log.debug("Got ACPI table with signature {s}", .{std.mem.toBytes(s)});
        },
    }
}

test {
    _ = sdt;
    _ = madt;
    _ = load_table;
}
