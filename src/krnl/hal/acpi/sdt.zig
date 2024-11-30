const std = @import("std");

const util = @import("util");

inline fn cast_signature(comptime sig: *const [4]u8) u32 {
    return @bitCast(sig.*);
}

pub const Signature = enum(u32) {
    RSDT = cast_signature("RSDT"),
    XSDT = cast_signature("XSDT"),
    APIC = cast_signature("APIC"),
    MCFG = cast_signature("MCFG"),
    HPET = cast_signature("HPET"),
    // FACP = cast_signature("FACP"),
    // WAET = cast_signature("WAET"),
    // BGRT = cast_signature("BGRT"),
    _,

    pub fn to_string(self: *const Signature) *const [4]u8 {
        return @as(*const [4]u8, @ptrCast(&self));
    }

    pub fn format(
        self: Signature,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll(self.to_string());
    }
};

pub const SystemDescriptorTableHeader = extern struct {
    signature: Signature align(1),
    length: u32 align(1),
    revision: u8 align(1),
    checksum: u8 align(1),
    oemid: [6]u8 align(1),
    oem_table_id: [8]u8 align(1),
    oem_revision: u32 align(1),
    creator_id: u32 align(1),
    creator_revision: u32 align(1),

    pub usingnamespace util.checksum.add_checksum(@This(), *const SystemDescriptorTableHeader, true);
};

test "basic header checksum" {
    const hdr1 = SystemDescriptorTableHeader{
        .signature = Signature.APIC,
        .checksum = 179,
        .length = @sizeOf(SystemDescriptorTableHeader),
        .creator_id = 4,
        .revision = 5,
        .oemid = std.mem.zeroes([6]u8),
        .oem_table_id = std.mem.zeroes([8]u8),
        .oem_revision = 1,
        .creator_revision = 2,
    };
    try std.testing.expectEqual(0, hdr1.compute_checksum());
    const hdr2 = SystemDescriptorTableHeader{
        .signature = Signature.APIC,
        .checksum = 180,
        .length = @sizeOf(SystemDescriptorTableHeader),
        .creator_id = 4,
        .revision = 5,
        .oemid = std.mem.zeroes([6]u8),
        .oem_table_id = std.mem.zeroes([8]u8),
        .oem_revision = 1,
        .creator_revision = 2,
    };
    try std.testing.expectError(util.checksum.ChecksumErrors.invalid_sdt_checksum, hdr2.verify_checksum());
}
