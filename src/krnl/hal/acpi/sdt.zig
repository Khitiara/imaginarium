const std = @import("std");

inline fn cast_signature(sig: *const [4]u8) u32 {
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

    pub fn from_string(sig: *const [4]u8) Signature {
        return @enumFromInt(cast_signature(sig));
    }

    pub fn to_string(self: Signature) [4]u8 {
        return @bitCast(@intFromEnum(self));
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
};
