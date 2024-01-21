pub const sdt = @import("acpi/sdt.zig");
const std = @import("std");

pub const XSDT = extern struct {
    header: sdt.SystemDescriptorTableHeader,

    pub fn entries(self: *const XSDT) []*const sdt.SystemDescriptorTableHeader {
        return std.mem.bytesAsSlice(*const sdt.SystemDescriptorTableHeader, @as([*]const u8, @ptrCast(self))[@sizeOf(sdt.SystemDescriptorTableHeader)..self.header.length]);
    }
};

test {
    _ = sdt;
    _ = XSDT;
}
