pub const sdt = @import("acpi/sdt.zig");
pub const rdsp = @import("acpi/rdsp.zig");
pub const madt = @import("acpi/madt.zig");
const std = @import("std");

pub const GlobalSdtLoadError = error{
    invalid_global_table_signature,
    invalid_global_table_alignment,
};

pub fn load_sdt(table: *align(4) const anyopaque) !void {
    const ptr: [*]align(4) const u8 = @ptrCast(table);
    const hdr: *const sdt.SystemDescriptorTableHeader = @ptrCast(ptr);
    switch (hdr.signature) {
        inline .RSDT, .XSDT => |sig| {
            const EntryType = switch (sig) {
                .RSDT => u32,
                .XSDT => u64,
                else => unreachable,
            };
            const begin = comptime std.mem.alignForward(usize, @sizeOf(sdt.SystemDescriptorTableHeader), 4);
            if (!std.mem.isAligned(hdr.length, 4)) {
                return error.invalid_global_table_alignment;
            }
            const slice = std.mem.bytesAsSlice(EntryType, ptr[begin..hdr.length]);

            for (slice) |e| {
                const t: *const sdt.SystemDescriptorTableHeader = @ptrFromInt(e);
                switch (t.signature) {
                    .APIC => madt.read_madt(@ptrCast(t)),
                else => {},
                }
            }
        },
        else => return error.invalid_global_table_signature,
    }
}

test {
    _ = sdt;
    _ = rdsp;
    _ = madt;
    _ = load_sdt;
}
